//
//  AutoNetClientConnection.swift
//
//  Created by Rodolfo Aramayo on 4/2/22.
//  Copyright © 2020 Apple, Inc. All rights reserved.
//

import Foundation
import Network

protocol AutoNetClientConnectionDelegate: AnyObject {
    func didReceiveData(_ data: Data)
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, *)
final class AutoNetClientConnection {
    private enum AuthenticationState {
        case transportConnecting
        case awaitingChallenge
        case awaitingAccepted(ROBControlAuthChallenge, ROBControlAuthProof)
        case authenticated
        case stopped
    }

    private static let authenticationTimeout: TimeInterval = 5

    let nwConnection: NWConnection
    private let transportMode: AutoNetTransportMode
    private let credential: ROBControlCredential?
    private let queue = DispatchQueue(label: "com.orbitusrobotics.rplidar.transport")

    weak var delegate: AutoNetClientConnectionDelegate?
    var readinessDidChangeCallback: ((Bool) -> Void)?
    var didStopCallback: ((Error?) -> Void)?

    private var hasStarted = false
    private var isStopped = false
    private var isReady = false
    private var isReceiving = false
    private var nextOutgoingSequence: UInt64 = 1
    private var authenticationState: AuthenticationState = .transportConnecting
    private var authenticationTimeoutWorkItem: DispatchWorkItem?

    init(
        nwConnection: NWConnection,
        transportMode: AutoNetTransportMode,
        credential: ROBControlCredential?
    ) {
        self.nwConnection = nwConnection
        self.transportMode = transportMode
        self.credential = credential
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.hasStarted, !self.isStopped else { return }
            self.hasStarted = true
            print("client: connection will start using \(self.transportMode)")
            self.nwConnection.stateUpdateHandler = { [weak self] state in
                self?.stateDidChange(to: state)
            }
            self.nwConnection.start(queue: self.queue)
        }
    }

    private func stateDidChange(to state: NWConnection.State) {
        guard !isStopped else { return }

        switch state {
        case .waiting(let error):
            print("client: connection waiting - \(error)")
            setReady(false)
        case .ready:
            switch authenticationState {
            case .transportConnecting:
                beginV2Authentication()
            case .authenticated:
                setReady(true)
                beginReceivingIfNeeded()
            case .awaitingChallenge, .awaitingAccepted, .stopped:
                break
            }
        case .failed(let error):
            print("client: connection failed - \(error)")
            stopLocked(error: error)
        case .cancelled:
            stopLocked(error: nil)
        case .setup, .preparing:
            setReady(false)
        @unknown default:
            setReady(false)
        }
    }

    private func beginV2Authentication() {
        guard credential != nil else {
            stopLocked(error: AutoNetTransportError.pairingRequired)
            return
        }
        authenticationState = .awaitingChallenge
        let timeout = DispatchWorkItem { [weak self] in
            self?.stopLocked(error: AutoNetTransportError.authenticationFailed)
        }
        authenticationTimeoutWorkItem = timeout
        queue.asyncAfter(deadline: .now() + Self.authenticationTimeout, execute: timeout)
        beginReceivingIfNeeded()
    }

    private func setReady(_ ready: Bool) {
        guard isReady != ready else { return }
        isReady = ready
        readinessDidChangeCallback?(ready)
    }

    private func beginReceivingIfNeeded() {
        guard !isReceiving, !isStopped else { return }
        isReceiving = true
        receiveNextMessage()
    }

    private func receiveNextMessage() {
        guard !isStopped else {
            isReceiving = false
            return
        }

        nwConnection.receiveMessage { [weak self] data, context, _, error in
            guard let self, !self.isStopped else { return }
            if let error {
                self.stopLocked(error: error)
                return
            }
            guard let messageType = self.transportMode.messageType(from: context),
                  let data else {
                self.stopLocked(error: NWError.posix(.EPROTO))
                return
            }

            if !self.isReady {
                self.handleAuthenticationMessage(type: messageType, data: data)
                return
            }

            switch messageType {
            case .sendData, .setAutomationScript, .lidarTelemetry,
                 .pairingChallenge, .pairingProof, .pairingAccepted, .pairingRejected, .invalid:
                // A sensor publisher has no inbound application authority.
                self.stopLocked(error: NWError.posix(.EPROTO))
                return
            }
        }
    }

    private func handleAuthenticationMessage(type: DataMessageType, data: Data) {
        guard let credential else {
            stopLocked(error: AutoNetTransportError.pairingRequired)
            return
        }

        switch authenticationState {
        case .awaitingChallenge:
            guard type == .pairingChallenge,
                  let challenge = ROBControlAuthChallenge(data),
                  challenge.robotID == credential.robotID else {
                stopLocked(error: AutoNetTransportError.authenticationFailed)
                return
            }
            do {
                let proof = try ROBControlAuthenticator.makeProof(challenge: challenge, credential: credential)
                authenticationState = .awaitingAccepted(challenge, proof)
                sendFrame(type: .pairingProof, data: proof.encoded) { [weak self] error in
                    guard let self else { return }
                    if let error { self.stopLocked(error: error) } else { self.receiveNextMessage() }
                }
            } catch {
                stopLocked(error: error)
            }

        case .awaitingAccepted(let challenge, let proof):
            guard type == .pairingAccepted,
                  let accepted = ROBControlAuthAccepted(data),
                  ROBControlAuthenticator.validate(accepted, proof: proof, challenge: challenge, credential: credential) else {
                stopLocked(error: AutoNetTransportError.authenticationFailed)
                return
            }
            authenticationTimeoutWorkItem?.cancel()
            authenticationTimeoutWorkItem = nil
            authenticationState = .authenticated
            setReady(true)
            print("client: Cerebro certificate pin and pairing proof accepted")
            receiveNextMessage()

        case .transportConnecting, .authenticated, .stopped:
            stopLocked(error: NWError.posix(.EPROTO))
        }
    }

    func sendLidarTelemetry(data: Data) {
        queue.async { [weak self] in
            guard let self, self.isReady, !self.isStopped else { return }
            guard self.credential?.effectiveRole == .lidarPublisher else {
                self.stopLocked(
                    error: AutoNetTransportError.roleMismatch(
                        expected: .lidarPublisher,
                        actual: self.credential?.effectiveRole ?? .operatorController
                    )
                )
                return
            }
            guard data.count <= 4 * 1024 * 1024 else {
                print("client: refusing oversized message of \(data.count) bytes")
                return
            }
            let sequence = self.nextOutgoingSequence
            guard sequence > 0 else {
                self.stopLocked(error: NWError.posix(.EOVERFLOW))
                return
            }
            self.nextOutgoingSequence &+= 1
            self.sendFrame(
                type: .lidarTelemetry,
                data: data,
                identifier: "LidarTelemetry-\(sequence)"
            ) { [weak self] error in
                if let error { self?.stopLocked(error: error) }
            }
        }
    }

    private func sendFrame(
        type: DataMessageType,
        data: Data,
        identifier: String? = nil,
        completion: @escaping (NWError?) -> Void
    ) {
        guard !isStopped else { return }
        let message = transportMode.makeMessage(type: type)
        let context = NWConnection.ContentContext(
            identifier: identifier ?? "ROBControl.\(type.rawValue)",
            metadata: [message]
        )
        nwConnection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed(completion))
    }

    func stop() {
        queue.async { [weak self] in self?.stopLocked(error: nil) }
    }

    private func stopLocked(error: Error?) {
        guard !isStopped else { return }
        isStopped = true
        authenticationState = .stopped
        authenticationTimeoutWorkItem?.cancel()
        authenticationTimeoutWorkItem = nil
        isReceiving = false
        setReady(false)
        nwConnection.stateUpdateHandler = nil
        nwConnection.cancel()

        let callback = didStopCallback
        didStopCallback = nil
        readinessDidChangeCallback = nil
        callback?(error)
    }
}
