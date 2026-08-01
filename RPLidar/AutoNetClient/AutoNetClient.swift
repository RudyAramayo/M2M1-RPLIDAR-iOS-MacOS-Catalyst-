//
//  AutoNetClient.swift
//
//  Created by Rodolfo Aramayo on 4/1/22.
//  Copyright © 2020 Apple, Inc. All rights reserved.
//

import Dispatch
import Foundation
import Network

@objc public protocol AutoNetClientDataDelegate {
    func didReceiveData(_ data: NSData)
}

/// RPLidar publisher transport. It connects only to Cerebro's v2 QUIC/TLS
/// service and accepts only a role-scoped lidarPublisher credential.
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
@objcMembers public final class AutoNetClient: NSObject, AutoNetClientConnectionDelegate {
    public static let defaultService = ROBControlPairing.serviceType
    public static let pairingCodeFormat = "ROBCTL2:<base64 lidarPublisher credential>"

    var connection: AutoNetClientConnection?
    public var host: NWEndpoint.Host?
    public var port: NWEndpoint.Port?
    public var service: String? = ""
    public var browser: NWBrowser?
    public var isConnected = false
    public var dataDelegate: AutoNetClientDataDelegate?

    private var generation: UInt64 = 0
    private var reconnectAttempt = 0
    private var isExplicitlyStopped = false

    public init(service: String) {
        self.service = service
        super.init()
        guard service == Self.defaultService else {
            print("RPLidar publisher refused unsupported Bonjour service: \(service)")
            return
        }
        startBrowsing()
    }

    public init(host: String, port: UInt16) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)
        self.service = nil
        super.init()
        performOnMain { [weak self] in
            self?.beginManualConnection(startImmediately: false, resetBackoff: true)
        }
    }

    /// Installs the out-of-band code shown by Cerebro. ROBControlPairing
    /// validates the pinned robot identity and application secret, then stores
    /// the credential in this device's Keychain. The code is never logged,
    /// advertised, or placed in UserDefaults.
    @objc(installPairingCode:error:)
    public func installPairingCode(
        _ pairingCode: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSError?>?
    ) -> Bool {
        do {
            try ROBControlPairing.installPairingCode(pairingCode)
            errorPointer?.pointee = nil
            performOnMain { [weak self] in
                guard let self else { return }
                if self.service != nil {
                    self.beginBrowsing(resetBackoff: true)
                } else {
                    self.beginManualConnection(startImmediately: true, resetBackoff: true)
                }
            }
            return true
        } catch {
            errorPointer?.pointee = error as NSError
            return false
        }
    }

    @objc(removePairingCodeWithError:)
    public func removePairingCode(
        _ errorPointer: AutoreleasingUnsafeMutablePointer<NSError?>?
    ) -> Bool {
        do {
            try ROBControlPairing.removePairing()
            errorPointer?.pointee = nil
            performOnMain { [weak self] in
                guard let self,
                      self.service == nil || self.service == Self.defaultService else {
                    return
                }
                self.stop()
            }
            return true
        } catch {
            errorPointer?.pointee = error as NSError
            return false
        }
    }

    public var pairingStatus: String {
        ROBControlPairing.isPaired ? "paired" : "not_paired"
    }

    public var isPairingConfigured: Bool {
        ROBControlPairing.isPaired
    }

    public var publisherDeviceID: UUID? {
        ROBControlPairing.pairedPublisherDeviceID()
    }

    public func startBrowsing() {
        performOnMain { [weak self] in
            guard let self else { return }
            if self.service == nil {
                self.beginManualConnection(startImmediately: true, resetBackoff: true)
            } else {
                self.beginBrowsing(resetBackoff: true)
            }
        }
    }

    public func start() {
        performOnMain { [weak self] in
            guard let self else { return }
            self.isExplicitlyStopped = false
            if let connection = self.connection {
                connection.start()
            } else if self.service == nil {
                self.beginManualConnection(startImmediately: true, resetBackoff: true)
            } else if self.browser == nil {
                self.beginBrowsing(resetBackoff: true)
            }
        }
    }

    public func connectionDescription() -> String {
        connection?.nwConnection.debugDescription ?? "No active AutoNet connection"
    }

    public func stop() {
        performOnMain { [weak self] in
            guard let self else { return }
            self.isExplicitlyStopped = true
            self.generation &+= 1
            self.isConnected = false

            self.browser?.stateUpdateHandler = nil
            self.browser?.browseResultsChangedHandler = nil
            self.browser?.cancel()
            self.browser = nil

            self.connection?.stop()
            self.connection = nil
        }
    }

    public func publishLidarTelemetry(_ data: Data) {
        performOnMain { [weak self] in
            self?.connection?.sendLidarTelemetry(data: data)
        }
    }

    func didReceiveData(_ data: Data) {
        dataDelegate?.didReceiveData(data as NSData)
    }

    private func beginBrowsing(resetBackoff: Bool) {
        precondition(Thread.isMainThread)
        guard let service, service == Self.defaultService else {
            isConnected = false
            print("RPLidar publisher supports only \(Self.defaultService)")
            return
        }

        let mode: AutoNetTransportMode
        do {
            mode = try AutoNetTransportMode(service: service)
        } catch {
            isConnected = false
            print("client: \(error.localizedDescription)")
            return
        }

        isExplicitlyStopped = false
        if resetBackoff {
            reconnectAttempt = 0
        }
        generation &+= 1
        let currentGeneration = generation
        isConnected = false

        browser?.stateUpdateHandler = nil
        browser?.browseResultsChangedHandler = nil
        browser?.cancel()
        browser = nil
        connection?.stop()
        connection = nil

        let browseParameters = NWParameters.udp
        browseParameters.includePeerToPeer = true
        let newBrowser = NWBrowser(
            for: .bonjour(type: service, domain: nil),
            using: browseParameters
        )
        browser = newBrowser

        newBrowser.stateUpdateHandler = { [weak self, weak newBrowser] state in
            DispatchQueue.main.async {
                guard let self,
                      let newBrowser,
                      self.generation == currentGeneration,
                      self.browser === newBrowser else { return }
                if case .failed(let error) = state {
                    print("client: browser failed - \(error)")
                    newBrowser.cancel()
                    self.browser = nil
                    self.scheduleReconnect(expectedGeneration: currentGeneration)
                }
            }
        }

        newBrowser.browseResultsChangedHandler = { [weak self, weak newBrowser] results, _ in
            DispatchQueue.main.async {
                guard let self,
                      let newBrowser,
                      self.generation == currentGeneration,
                      self.browser === newBrowser,
                      self.connection == nil else { return }

                guard let pairedRobotID = ROBControlPairing.pairedRobotID() else {
                    print("client: install a lidarPublisher credential before selecting Cerebro")
                    return
                }
                let selected = results
                    .filter { ROBControlPairing.robotID(fromBonjourMetadata: $0.metadata) == pairedRobotID }
                    .sorted { $0.endpoint.debugDescription < $1.endpoint.debugDescription }
                    .first
                guard let result = selected else { return }
                self.connect(
                    to: result.endpoint,
                    mode: mode,
                    generation: currentGeneration
                )
            }
        }

        newBrowser.start(queue: .main)
    }

    private func beginManualConnection(startImmediately: Bool, resetBackoff: Bool) {
        precondition(Thread.isMainThread)
        guard let host, let port else { return }

        isExplicitlyStopped = false
        if resetBackoff {
            reconnectAttempt = 0
        }
        generation &+= 1
        let currentGeneration = generation
        isConnected = false
        connection?.stop()
        connection = nil

        do {
            let mode = AutoNetTransportMode.v2
            let credential = try ROBControlPairing.clientAuthenticationMaterial()
            let nwConnection = NWConnection(host: host, port: port, using: try mode.makeClientParameters())
            install(
                nwConnection: nwConnection,
                mode: mode,
                credential: credential,
                generation: currentGeneration,
                startImmediately: startImmediately
            )
        } catch {
            print("client: manual QUIC connection not started - \(error.localizedDescription)")
        }
    }

    private func connect(
        to endpoint: NWEndpoint,
        mode: AutoNetTransportMode,
        generation currentGeneration: UInt64
    ) {
        precondition(Thread.isMainThread)
        guard generation == currentGeneration, connection == nil else { return }

        do {
            let credential = try ROBControlPairing.clientAuthenticationMaterial()
            let nwConnection = NWConnection(to: endpoint, using: try mode.makeClientParameters())
            install(
                nwConnection: nwConnection,
                mode: mode,
                credential: credential,
                generation: currentGeneration,
                startImmediately: true
            )
        } catch {
            // Pairing/authentication failure is terminal for this attempt.
            print("client: connection not started - \(error.localizedDescription)")
        }
    }

    private func install(
        nwConnection: NWConnection,
        mode: AutoNetTransportMode,
        credential: ROBControlCredential?,
        generation currentGeneration: UInt64,
        startImmediately: Bool
    ) {
        let clientConnection = AutoNetClientConnection(
            nwConnection: nwConnection,
            transportMode: mode,
            credential: credential
        )
        clientConnection.delegate = self

        clientConnection.readinessDidChangeCallback = { [weak self, weak clientConnection] ready in
            DispatchQueue.main.async {
                guard let self,
                      let clientConnection,
                      self.generation == currentGeneration,
                      self.connection === clientConnection else { return }
                self.isConnected = ready
                if ready {
                    self.reconnectAttempt = 0
                    self.browser?.stateUpdateHandler = nil
                    self.browser?.browseResultsChangedHandler = nil
                    self.browser?.cancel()
                    self.browser = nil
                }
            }
        }

        clientConnection.didStopCallback = { [weak self, weak clientConnection] error in
            DispatchQueue.main.async {
                guard let self,
                      let clientConnection,
                      self.generation == currentGeneration,
                      self.connection === clientConnection else { return }
                self.isConnected = false
                self.connection = nil
                if let error {
                    print("client: connection stopped - \(error.localizedDescription)")
                }
                self.scheduleReconnect(expectedGeneration: currentGeneration)
            }
        }

        connection = clientConnection
        if startImmediately {
            clientConnection.start()
        }
    }

    private func scheduleReconnect(expectedGeneration: UInt64) {
        precondition(Thread.isMainThread)
        guard !isExplicitlyStopped, generation == expectedGeneration else { return }

        let exponent = min(reconnectAttempt, 5)
        let delay = min(pow(2.0, Double(exponent)), 30.0) + Double.random(in: 0...0.5)
        reconnectAttempt += 1

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  !self.isExplicitlyStopped,
                  self.generation == expectedGeneration,
                  self.connection == nil else { return }
            if self.service == nil {
                self.beginManualConnection(startImmediately: true, resetBackoff: false)
            } else {
                self.beginBrowsing(resetBackoff: false)
            }
        }
    }

    private func performOnMain(_ operation: @escaping () -> Void) {
        if Thread.isMainThread {
            operation()
        } else {
            DispatchQueue.main.async(execute: operation)
        }
    }
}
