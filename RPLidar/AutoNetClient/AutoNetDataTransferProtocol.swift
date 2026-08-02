//
//  AutoNetDataTransferProtocol.swift
//  RPLidar
//
//  RPLidar uses only the reliable v2 QUIC stream over UDP. Cerebro presents a
//  persistent P-256 identity, this app pins its leaf certificate during
//  pairing, and both sides prove possession of a role-scoped pairing secret
//  before any telemetry is accepted.
//

import CryptoKit
import Foundation
import Network
import Security

enum DataMessageType: UInt32 {
  case invalid = 0
  case sendData = 1
  case setAutomationScript = 2
  case pairingChallenge = 3
  case pairingProof = 4
  case pairingAccepted = 5
  case pairingRejected = 6
  case lidarTelemetry = 7
}

enum AutoNetTransportError: LocalizedError {
  case unsupportedService(String)
  case pairingRequired
  case invalidPairingCode
  case keychain(OSStatus)
  case randomGeneration(OSStatus)
  case authenticationFailed
  case credentialRejected
  case roleMismatch(expected: ROBControlPeerRole, actual: ROBControlPeerRole)

  var errorDescription: String? {
    switch self {
    case .unsupportedService(let service):
      return "Unsupported robot-control Bonjour service: \(service)"
    case .pairingRequired:
      return "No Cerebro Lidar-publisher pairing credential is installed."
    case .invalidPairingCode:
      return "The Cerebro pairing code is invalid or incomplete."
    case .keychain(let status):
      return "Unable to access the robot-control pairing key in Keychain (OSStatus \(status))."
    case .randomGeneration(let status):
      return "Unable to create a robot-control pairing key (OSStatus \(status))."
    case .authenticationFailed:
      return "Cerebro authentication did not complete."
    case .credentialRejected:
      return "Cerebro rejected this saved Lidar-publisher credential. Replace it with a fresh ROBCTL2 code."
    case .roleMismatch(let expected, let actual):
      return "This app requires a \(expected.rawValue) credential; the supplied credential grants \(actual.rawValue)."
    }
  }
}

enum ROBControlPeerRole: String, Codable, CaseIterable {
  case operatorController
  case lidarPublisher
}

struct ROBControlCredential: Codable, Equatable {
  let version: Int
  let robotID: UUID
  let controllerID: UUID
  let serviceType: String
  let applicationProtocol: String
  let certificateSHA256: Data
  let sharedSecret: Data
  let role: ROBControlPeerRole?
  let deviceName: String?
  let issuedAtMilliseconds: UInt64?

  var isValid: Bool {
    let normalizedName = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines)
    return version == 2 && serviceType == ROBControlPairing.serviceType
      && applicationProtocol == ROBControlPairing.applicationProtocol
      && certificateSHA256.count == 32 && sharedSecret.count == 32
      && (normalizedName == nil
        || (normalizedName!.count >= 1 && normalizedName!.count <= 80
          && normalizedName!.rangeOfCharacter(from: .controlCharacters) == nil))
      && (issuedAtMilliseconds == nil || issuedAtMilliseconds! > 0)
  }

  /// Credentials created before per-device roles existed decode as the legacy
  /// operator role. The RPLidar client rejects that role and accepts only a
  /// newly issued lidarPublisher credential.
  var effectiveRole: ROBControlPeerRole {
    role ?? .operatorController
  }

  init(
    version: Int,
    robotID: UUID,
    controllerID: UUID,
    serviceType: String,
    applicationProtocol: String,
    certificateSHA256: Data,
    sharedSecret: Data,
    role: ROBControlPeerRole? = nil,
    deviceName: String? = nil,
    issuedAtMilliseconds: UInt64? = nil
  ) {
    self.version = version
    self.robotID = robotID
    self.controllerID = controllerID
    self.serviceType = serviceType
    self.applicationProtocol = applicationProtocol
    self.certificateSHA256 = certificateSHA256
    self.sharedSecret = sharedSecret
    self.role = role
    self.deviceName = deviceName
    self.issuedAtMilliseconds = issuedAtMilliseconds
  }
}

/// Keychain-backed pairing material transferred out-of-band from Cerebro to a
/// trusted publisher. Bonjour contains only routing metadata; the certificate
/// pin and shared secret exist only in this code and the two devices' Keychains.
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
@objcMembers public final class ROBControlPairing: NSObject {
  public static let serviceType = "_robctl._udp"
  public static let applicationProtocol = "robctl/2"
  static let requiredClientRole = ROBControlPeerRole.lidarPublisher

  private static let keychainService = "com.orbitusrobotics.robctl.v2"
  private static let clientProfileAccount = "paired-cerebro-profile"
  private static let environmentKey = "ROB_CONTROL_PAIRING_SECRET"
  private static let environmentBootstrapCompletedKey =
    "com.orbitusrobotics.robctl.v2.environment-bootstrap-completed"
  private static let pairingPrefix = "ROBCTL2:"
  private static let verifyQueue = DispatchQueue(label: "com.orbitusrobotics.robctl.v2.verify")

  public static var isPaired: Bool {
    guard let credential = try? loadCredential(account: clientProfileAccount) else { return false }
    return credential.isValid && credential.effectiveRole == requiredClientRole
  }

  /// True when a local Keychain item exists even if it is malformed, legacy,
  /// or has the wrong role. The UI uses this to keep replacement and removal
  /// available for credentials that cannot be used for a connection.
  public static var hasStoredCredential: Bool {
    do {
      return try loadData(account: clientProfileAccount) != nil
    } catch {
      return true
    }
  }

  /// Installs a code transferred directly from Cerebro. Replacing a code
  /// removes the previous local pairing; server-side revocation remains an
  /// explicit action in Cerebro.
  public static func installPairingCode(_ code: String) throws {
    let credential = try decodePairingCode(code)
    try validatePublisherCredential(credential)
    disableEnvironmentBootstrap()
    try storeCredential(credential, account: clientProfileAccount)
  }

  static func decodePairingCode(_ code: String) throws -> ROBControlCredential {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.range(of: pairingPrefix, options: [.anchored, .caseInsensitive]) != nil else {
      throw AutoNetTransportError.invalidPairingCode
    }
    let normalized =
      trimmed
      .replacingOccurrences(of: pairingPrefix, with: "", options: [.anchored, .caseInsensitive])
      .replacingOccurrences(of: " ", with: "")
    guard let payload = Data(base64Encoded: normalized),
      payload.count <= 4_096,
      let credential = try? JSONDecoder().decode(ROBControlCredential.self, from: payload),
      credential.isValid
    else {
      throw AutoNetTransportError.invalidPairingCode
    }
    return credential
  }

  public static func removePairing() throws {
    disableEnvironmentBootstrap()
    let status = SecItemDelete(genericQuery(account: clientProfileAccount) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw AutoNetTransportError.keychain(status)
    }
  }

  static func clientAuthenticationMaterial() throws -> ROBControlCredential {
    guard let credential = try loadCredential(account: clientProfileAccount) else {
      throw AutoNetTransportError.pairingRequired
    }
    try validatePublisherCredential(credential)
    return credential
  }

  /// Imports the developer launch-scheme credential, at most once, before
  /// discovery starts. Normal credential reads never write to Keychain.
  /// Explicit Pair or Forget actions permanently disable this bootstrap.
  static func bootstrapEnvironmentCredentialIfNeeded() throws {
    let storedCredential = try loadCredential(account: clientProfileAccount)
    if let storedCredential {
      disableEnvironmentBootstrap()
      try validatePublisherCredential(storedCredential)
      return
    }

    let candidate = try environmentBootstrapCredential(
      storedCredential: nil,
      environmentCode: ProcessInfo.processInfo.environment[environmentKey],
      bootstrapAllowed: !UserDefaults.standard.bool(forKey: environmentBootstrapCompletedKey)
    )
    guard let candidate else { return }
    try storeCredential(candidate, account: clientProfileAccount)
    disableEnvironmentBootstrap()
  }

  /// Pure selection helper used by the standalone migration fixture.
  static func environmentBootstrapCredential(
    storedCredential: ROBControlCredential?,
    environmentCode: String?,
    bootstrapAllowed: Bool
  ) throws -> ROBControlCredential? {
    guard storedCredential == nil,
      bootstrapAllowed,
      let environmentCode,
      !environmentCode.isEmpty,
      environmentCode.uppercased().hasPrefix(pairingPrefix)
    else {
      return nil
    }
    let credential = try decodePairingCode(environmentCode)
    try validatePublisherCredential(credential)
    return credential
  }

  static func validatePublisherCredential(_ credential: ROBControlCredential) throws {
    guard credential.isValid else {
      throw AutoNetTransportError.invalidPairingCode
    }
    guard credential.effectiveRole == requiredClientRole else {
      throw AutoNetTransportError.roleMismatch(
        expected: requiredClientRole,
        actual: credential.effectiveRole
      )
    }
  }

  static func pairedPublisherDeviceID() -> UUID? {
    guard let credential = try? clientAuthenticationMaterial() else { return nil }
    return credential.controllerID
  }

  static func makeV2ClientParameters() throws -> NWParameters {
    let credential = try clientAuthenticationMaterial()
    return makeV2ClientParameters(pinnedCertificateSHA256: credential.certificateSHA256)
  }

  /// Internal injection point used by localhost transport fixtures.
  static func makeV2ClientParameters(pinnedCertificateSHA256 expectedFingerprint: Data)
    -> NWParameters
  {
    precondition(expectedFingerprint.count == 32)
    let quic = NWProtocolQUIC.Options(alpn: [applicationProtocol])
    quic.direction = .bidirectional
    quic.idleTimeout = 10_000
    let securityOptions = quic.securityProtocolOptions
    sec_protocol_options_set_min_tls_protocol_version(securityOptions, .TLSv13)
    sec_protocol_options_set_verify_block(
      securityOptions,
      { _, trust, complete in
        let trustReference = sec_trust_copy_ref(trust).takeRetainedValue()
        guard let chain = SecTrustCopyCertificateChain(trustReference) as? [SecCertificate],
          let leaf = chain.first
        else {
          complete(false)
          return
        }
        let leafData = SecCertificateCopyData(leaf) as Data
        complete(Data(SHA256.hash(data: leafData)) == expectedFingerprint)
      }, verifyQueue)
    return framedQUICParameters(options: quic)
  }

  static func pairedRobotID() -> UUID? {
    try? loadCredential(account: clientProfileAccount)?.robotID
  }

  static func robotID(fromBonjourMetadata metadata: NWBrowser.Result.Metadata) -> UUID? {
    guard case .bonjour(let txtRecord) = metadata,
      txtRecord["ver"] == "2",
      txtRecord["alpn"] == applicationProtocol,
      let string = txtRecord["robot_id"]
    else { return nil }
    return UUID(uuidString: string)
  }

  static func requiresPairingReplacement(after error: Error) -> Bool {
    if let transportError = error as? AutoNetTransportError {
      switch transportError {
      case .credentialRejected:
        return true
      default:
        break
      }
    }
    if let networkError = error as? NWError {
      switch networkError {
      case .tls:
        return true
      default:
        break
      }
    }
    return false
  }

  private static func disableEnvironmentBootstrap() {
    UserDefaults.standard.set(true, forKey: environmentBootstrapCompletedKey)
  }

  private static func framedQUICParameters(options: NWProtocolQUIC.Options) -> NWParameters {
    let parameters = NWParameters(quic: options)
    parameters.allowLocalEndpointReuse = true
    parameters.includePeerToPeer = true
    parameters.serviceClass = .signaling
    parameters.defaultProtocolStack.applicationProtocols.insert(
      NWProtocolFramer.Options(definition: ROBV2ControlFramer.definition),
      at: 0
    )
    return parameters
  }

  private static func genericQuery(account: String) -> [String: Any] {
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: account,
    ]
  }

  private static func loadData(account: String) throws -> Data? {
    var query = genericQuery(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecSuccess {
      return result as? Data
    }
    guard status == errSecItemNotFound else {
      throw AutoNetTransportError.keychain(status)
    }

    return nil
  }

  private static func storeData(_ data: Data, account: String) throws {
    let updateStatus = SecItemUpdate(
      genericQuery(account: account) as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    if updateStatus == errSecSuccess {
      return
    }
    guard updateStatus == errSecItemNotFound else {
      throw AutoNetTransportError.keychain(updateStatus)
    }

    var addQuery = genericQuery(account: account)
    addQuery[kSecValueData as String] = data
    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw AutoNetTransportError.keychain(addStatus)
    }
  }

  private static func loadCredential(account: String) throws -> ROBControlCredential? {
    guard let data = try loadData(account: account) else { return nil }
    guard let credential = try? JSONDecoder().decode(ROBControlCredential.self, from: data),
      credential.isValid
    else {
      throw AutoNetTransportError.invalidPairingCode
    }
    return credential
  }

  private static func storeCredential(_ credential: ROBControlCredential, account: String) throws {
    guard credential.isValid else { throw AutoNetTransportError.invalidPairingCode }
    try storeData(try JSONEncoder().encode(credential), account: account)
  }


}

struct ROBControlAuthChallenge {
  static let encodedSize = 65
  let sessionID: Data
  let serverNonce: Data
  let robotID: UUID
  var encoded: Data {
    var data = Data([1])
    data.append(sessionID)
    data.append(serverNonce)
    data.append(robotID.robControlBytes)
    return data
  }
  init(sessionID: Data, serverNonce: Data, robotID: UUID) {
    self.sessionID = sessionID
    self.serverNonce = serverNonce
    self.robotID = robotID
  }
  init?(_ data: Data) {
    guard data.count == Self.encodedSize, data[0] == 1,
      let robotID = UUID(robControlBytes: data.subdata(in: 49..<65))
    else { return nil }
    self.sessionID = data.subdata(in: 1..<17)
    self.serverNonce = data.subdata(in: 17..<49)
    self.robotID = robotID
  }
}

struct ROBControlAuthProof {
  static let encodedSize = 97
  let sessionID: Data
  let controllerID: UUID
  let clientNonce: Data
  let mac: Data
  var encoded: Data {
    var data = Data([1])
    data.append(sessionID)
    data.append(controllerID.robControlBytes)
    data.append(clientNonce)
    data.append(mac)
    return data
  }
  init(sessionID: Data, controllerID: UUID, clientNonce: Data, mac: Data) {
    self.sessionID = sessionID
    self.controllerID = controllerID
    self.clientNonce = clientNonce
    self.mac = mac
  }
  init?(_ data: Data) {
    guard data.count == Self.encodedSize, data[0] == 1,
      let controllerID = UUID(robControlBytes: data.subdata(in: 17..<33))
    else { return nil }
    self.sessionID = data.subdata(in: 1..<17)
    self.controllerID = controllerID
    self.clientNonce = data.subdata(in: 33..<65)
    self.mac = data.subdata(in: 65..<97)
  }
}

struct ROBControlAuthAccepted {
  static let encodedSize = 65
  let sessionID: Data
  let controllerID: UUID
  let mac: Data
  var encoded: Data {
    var data = Data([1])
    data.append(sessionID)
    data.append(controllerID.robControlBytes)
    data.append(mac)
    return data
  }
  init(sessionID: Data, controllerID: UUID, mac: Data) {
    self.sessionID = sessionID
    self.controllerID = controllerID
    self.mac = mac
  }
  init?(_ data: Data) {
    guard data.count == Self.encodedSize, data[0] == 1,
      let controllerID = UUID(robControlBytes: data.subdata(in: 17..<33))
    else { return nil }
    self.sessionID = data.subdata(in: 1..<17)
    self.controllerID = controllerID
    self.mac = data.subdata(in: 33..<65)
  }
}

enum ROBControlAuthenticator {
  private static let transcriptDomain = Data("robctl/2\0".utf8)
  private static let clientDomain = Data("ROBCTL-AUTH-V1/CLIENT-PROOF\0".utf8)
  private static let serverDomain = Data("ROBCTL-AUTH-V1/SERVER-ACCEPTED\0".utf8)

  static func makeChallenge(robotID: UUID) throws -> ROBControlAuthChallenge {
    ROBControlAuthChallenge(
      sessionID: try random(count: 16), serverNonce: try random(count: 32), robotID: robotID)
  }
  static func makeProof(challenge: ROBControlAuthChallenge, credential: ROBControlCredential) throws
    -> ROBControlAuthProof
  {
    let nonce = try random(count: 32)
    let transcript = makeTranscript(
      challenge: challenge, controllerID: credential.controllerID, clientNonce: nonce)
    return ROBControlAuthProof(
      sessionID: challenge.sessionID, controllerID: credential.controllerID, clientNonce: nonce,
      mac: hmac(domain: clientDomain, transcript: transcript, secret: credential.sharedSecret))
  }
  static func validate(
    _ proof: ROBControlAuthProof, challenge: ROBControlAuthChallenge,
    credential: ROBControlCredential
  ) -> Bool {
    guard proof.sessionID == challenge.sessionID, proof.controllerID == credential.controllerID,
      challenge.robotID == credential.robotID
    else { return false }
    var input = clientDomain
    input.append(
      makeTranscript(
        challenge: challenge, controllerID: proof.controllerID, clientNonce: proof.clientNonce))
    return HMAC<SHA256>.isValidAuthenticationCode(
      proof.mac, authenticating: input, using: SymmetricKey(data: credential.sharedSecret))
  }
  static func accepted(
    for proof: ROBControlAuthProof, challenge: ROBControlAuthChallenge,
    credential: ROBControlCredential
  ) -> ROBControlAuthAccepted {
    let transcript = makeTranscript(
      challenge: challenge, controllerID: proof.controllerID, clientNonce: proof.clientNonce)
    var input = serverDomain
    input.append(transcript)
    input.append(proof.mac)
    let mac = Data(
      HMAC<SHA256>.authenticationCode(
        for: input, using: SymmetricKey(data: credential.sharedSecret)))
    return ROBControlAuthAccepted(
      sessionID: proof.sessionID, controllerID: proof.controllerID, mac: mac)
  }
  static func validate(
    _ accepted: ROBControlAuthAccepted, proof: ROBControlAuthProof,
    challenge: ROBControlAuthChallenge, credential: ROBControlCredential
  ) -> Bool {
    guard accepted.sessionID == challenge.sessionID,
      accepted.controllerID == credential.controllerID
    else { return false }
    var input = serverDomain
    input.append(
      makeTranscript(
        challenge: challenge, controllerID: proof.controllerID, clientNonce: proof.clientNonce))
    input.append(proof.mac)
    return HMAC<SHA256>.isValidAuthenticationCode(
      accepted.mac, authenticating: input, using: SymmetricKey(data: credential.sharedSecret))
  }
  private static func makeTranscript(
    challenge: ROBControlAuthChallenge, controllerID: UUID, clientNonce: Data
  ) -> Data {
    var data = transcriptDomain
    data.append(challenge.encoded)
    data.append(controllerID.robControlBytes)
    data.append(clientNonce)
    return data
  }
  private static func hmac(domain: Data, transcript: Data, secret: Data) -> Data {
    var input = domain
    input.append(transcript)
    return Data(HMAC<SHA256>.authenticationCode(for: input, using: SymmetricKey(data: secret)))
  }
  private static func random(count: Int) throws -> Data {
    var data = Data(count: count)
    let status = data.withUnsafeMutableBytes {
      SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
    }
    guard status == errSecSuccess else { throw AutoNetTransportError.randomGeneration(status) }
    return data
  }
}

extension UUID {
  fileprivate var robControlBytes: Data {
    var value = uuid
    return withUnsafeBytes(of: &value) { Data($0) }
  }
  fileprivate init?(robControlBytes data: Data) {
    guard data.count == 16 else { return nil }
    var value: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0) }
    self.init(uuid: value)
  }
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
enum AutoNetTransportMode {
  case v2

  init(service: String) throws {
    guard service == ROBControlPairing.serviceType else {
      throw AutoNetTransportError.unsupportedService(service)
    }
    self = .v2
  }

  var serviceType: String {
    ROBControlPairing.serviceType
  }

  var framerDefinition: NWProtocolFramer.Definition {
    ROBV2ControlFramer.definition
  }

  func makeClientParameters() throws -> NWParameters {
    try ROBControlPairing.makeV2ClientParameters()
  }

  func makeMessage(type: DataMessageType) -> NWProtocolFramer.Message {
    let message = NWProtocolFramer.Message(definition: framerDefinition)
    message.autoNetMessageType = type
    return message
  }

  func messageType(from context: NWConnection.ContentContext?) -> DataMessageType? {
    guard
      let message = context?.protocolMetadata(definition: framerDefinition)
        as? NWProtocolFramer.Message
    else {
      return nil
    }
    return message.autoNetMessageType
  }
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
final class ROBV2ControlFramer: NWProtocolFramerImplementation {
  static let definition = NWProtocolFramer.Definition(implementation: ROBV2ControlFramer.self)
  static var label: String { "ROBControlV2" }

  private var nextOutputSequence: UInt64 = 1
  private var lastInputSequence: UInt64 = 0

  required init(framer: NWProtocolFramer.Instance) {}
  func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult { .ready }
  func wakeup(framer: NWProtocolFramer.Instance) {}
  func stop(framer: NWProtocolFramer.Instance) -> Bool { true }
  func cleanup(framer: NWProtocolFramer.Instance) {}

  func handleOutput(
    framer: NWProtocolFramer.Instance,
    message: NWProtocolFramer.Message,
    messageLength: Int,
    isComplete: Bool
  ) {
    guard messageLength <= ROBV2FrameHeader.maximumPayloadLength,
      messageLength >= 0,
      message.autoNetMessageType != .invalid,
      nextOutputSequence != UInt64.max
    else {
      framer.markFailed(error: NWError.posix(.EMSGSIZE))
      return
    }

    let header = ROBV2FrameHeader(
      type: message.autoNetMessageType,
      payloadLength: UInt32(messageLength),
      sequence: nextOutputSequence,
      messageID: UUID()
    )
    nextOutputSequence += 1
    framer.writeOutput(data: header.encodedData)
    do {
      try framer.writeOutputNoCopy(length: messageLength)
    } catch {
      framer.markFailed(error: NWError.posix(.EIO))
    }
  }

  func handleInput(framer: NWProtocolFramer.Instance) -> Int {
    while true {
      var parsedHeader: ROBV2FrameHeader?
      var malformed = false
      let headerSize = ROBV2FrameHeader.encodedSize
      let parsed = framer.parseInput(
        minimumIncompleteLength: headerSize,
        maximumLength: headerSize
      ) { buffer, _ in
        guard let buffer = buffer, buffer.count >= headerSize else { return 0 }
        parsedHeader = ROBV2FrameHeader(buffer)
        malformed = parsedHeader == nil
        return headerSize
      }

      guard parsed else { return headerSize }
      guard !malformed,
        let header = parsedHeader,
        header.sequence > lastInputSequence
      else {
        framer.markFailed(error: NWError.posix(.EPROTO))
        return 0
      }
      lastInputSequence = header.sequence

      let message = NWProtocolFramer.Message(definition: Self.definition)
      message.autoNetMessageType = header.type
      if !framer.deliverInputNoCopy(
        length: Int(header.payloadLength),
        message: message,
        isComplete: true
      ) {
        return 0
      }
    }
  }
}

private struct ROBV2FrameHeader {
  static let magic: UInt32 = 0x5243_544C  // "RCTL"
  static let version: UInt8 = 2
  static let encodedSize = 40
  static let maximumPayloadLength = 4 * 1024 * 1024

  let type: DataMessageType
  let payloadLength: UInt32
  let sequence: UInt64
  let messageID: [UInt8]

  init(type: DataMessageType, payloadLength: UInt32, sequence: UInt64, messageID: UUID) {
    self.type = type
    self.payloadLength = payloadLength
    self.sequence = sequence
    var uuid = messageID.uuid
    self.messageID = withUnsafeBytes(of: &uuid) { Array($0) }
  }

  init?(_ buffer: UnsafeMutableRawBufferPointer) {
    guard buffer.count >= Self.encodedSize,
      Self.readUInt32(buffer, offset: 0) == Self.magic,
      buffer[4] == Self.version,
      Int(buffer[5]) == Self.encodedSize,
      Self.readUInt16(buffer, offset: 8) == 0,
      Self.readUInt16(buffer, offset: 10) == 0,
      let type = DataMessageType(rawValue: UInt32(Self.readUInt16(buffer, offset: 6))),
      type != .invalid
    else {
      return nil
    }
    let length = Self.readUInt32(buffer, offset: 12)
    guard length <= UInt32(Self.maximumPayloadLength) else { return nil }

    self.type = type
    self.payloadLength = length
    self.sequence = Self.readUInt64(buffer, offset: 16)
    self.messageID = Array(UnsafeRawBufferPointer(rebasing: buffer[24..<40]))
  }

  var encodedData: Data {
    var data = Data(capacity: Self.encodedSize)
    data.appendBigEndian(Self.magic)
    data.append(Self.version)
    data.append(UInt8(Self.encodedSize))
    data.appendBigEndian(UInt16(type.rawValue))
    data.appendBigEndian(UInt16(0))  // flags
    data.appendBigEndian(UInt16(0))  // channel
    data.appendBigEndian(payloadLength)
    data.appendBigEndian(sequence)
    data.append(contentsOf: messageID)
    return data
  }

  private static func readUInt16(_ buffer: UnsafeMutableRawBufferPointer, offset: Int) -> UInt16 {
    return (UInt16(buffer[offset]) << 8) | UInt16(buffer[offset + 1])
  }

  private static func readUInt32(_ buffer: UnsafeMutableRawBufferPointer, offset: Int) -> UInt32 {
    return (UInt32(buffer[offset]) << 24) | (UInt32(buffer[offset + 1]) << 16)
      | (UInt32(buffer[offset + 2]) << 8) | UInt32(buffer[offset + 3])
  }

  private static func readUInt64(_ buffer: UnsafeMutableRawBufferPointer, offset: Int) -> UInt64 {
    var value: UInt64 = 0
    for index in offset..<(offset + 8) {
      value = (value << 8) | UInt64(buffer[index])
    }
    return value
  }
}

extension Data {
  fileprivate mutating func appendBigEndian(_ value: UInt16) {
    append(UInt8((value >> 8) & 0xff))
    append(UInt8(value & 0xff))
  }

  fileprivate mutating func appendBigEndian(_ value: UInt32) {
    append(UInt8((value >> 24) & 0xff))
    append(UInt8((value >> 16) & 0xff))
    append(UInt8((value >> 8) & 0xff))
    append(UInt8(value & 0xff))
  }

  fileprivate mutating func appendBigEndian(_ value: UInt64) {
    for shift in stride(from: 56, through: 0, by: -8) {
      append(UInt8((value >> UInt64(shift)) & 0xff))
    }
  }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension NWProtocolFramer.Message {
  fileprivate var autoNetMessageType: DataMessageType {
    get { self["ROBControlMessageType"] as? DataMessageType ?? .invalid }
    set { self["ROBControlMessageType"] = newValue }
  }
}
