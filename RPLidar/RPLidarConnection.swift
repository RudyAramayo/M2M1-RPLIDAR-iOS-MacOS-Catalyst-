import Foundation
import Darwin

enum RPLidarConnectionError: LocalizedError {
    case invalidIPAddress(String)
    case unreachable(host: String, port: UInt16, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidIPAddress(let host):
            return "Invalid lidar IP address: \(host)."
        case .unreachable(let host, let port, let reason):
            return "Lidar unavailable at \(host):\(port): \(reason). Check its power, IP address, and Wi-Fi connection."
        }
    }
}

struct RPLidarEndpoint {
    static let servicePort: UInt16 = 1445

    static var configuredHost: String {
        ProcessInfo.processInfo.environment["RPLIDAR_IP"]
            ?? UserDefaults.standard.string(forKey: "RPLidarIPAddress")
            ?? "192.168.11.1"
    }

    let host: String
    let port: UInt16

    init(host: String, port: UInt16 = servicePort) {
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.port = port
    }

    /// Run on the hardware queue. A numeric address avoids an unbounded DNS
    /// lookup; the nonblocking TCP connect has a deadline and always closes.
    /// This checks the service port, not just whether a host answers ping.
    func checkReachability(timeout: TimeInterval = 1) throws {
        guard !host.isEmpty, !host.utf8.contains(0), port != 0 else {
            throw RPLidarConnectionError.invalidIPAddress(host)
        }

        var hints = addrinfo()
        hints.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        var addresses: UnsafeMutablePointer<addrinfo>?
        let result = getaddrinfo(host, String(port), &hints, &addresses)
        guard result == 0, let addresses else {
            throw RPLidarConnectionError.invalidIPAddress(host)
        }
        defer { freeaddrinfo(addresses) }

        let address = addresses.pointee
        let descriptor = socket(address.ai_family, address.ai_socktype, address.ai_protocol)
        guard descriptor >= 0 else { throw connectionError(errno) }
        defer { Darwin.close(descriptor) }

        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw connectionError(errno)
        }
        if Darwin.connect(descriptor, address.ai_addr, address.ai_addrlen) == 0 {
            return
        }
        guard errno == EINPROGRESS else { throw connectionError(errno) }

        let deadline = ProcessInfo.processInfo.systemUptime + max(0, min(timeout, 5))
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw connectionError(ETIMEDOUT) }
            var event = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&event, 1, Int32(ceil(remaining * 1_000)))
            if ready < 0 {
                if errno == EINTR { continue }
                throw connectionError(errno)
            }
            guard ready > 0 else { throw connectionError(ETIMEDOUT) }
            var socketError: Int32 = 0
            var length = socklen_t(MemoryLayout.size(ofValue: socketError))
            guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0 else {
                throw connectionError(errno)
            }
            guard socketError == 0 else { throw connectionError(socketError) }
            return
        }
    }

    private func connectionError(_ code: Int32) -> RPLidarConnectionError {
        .unreachable(host: host, port: port, reason: String(cString: strerror(code)))
    }
}

/// Owned by the hardware queue. Only one delayed retry may exist, and a
/// manual reconnect or stop invalidates callbacks already queued for delivery.
final class RPLidarRetryScheduler {
    private let queue: DispatchQueue
    private var workItem: DispatchWorkItem?
    private var generation: UInt64 = 0

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    var isScheduled: Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        return workItem != nil
    }

    func schedule(after delay: TimeInterval, _ retry: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard workItem == nil else { return }
        let expectedGeneration = generation
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.generation == expectedGeneration else { return }
            self.workItem = nil
            retry()
        }
        workItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancel() {
        dispatchPrecondition(condition: .onQueue(queue))
        generation &+= 1
        workItem?.cancel()
        workItem = nil
    }
}
