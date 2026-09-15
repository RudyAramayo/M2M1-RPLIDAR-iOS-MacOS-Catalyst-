// swiftc RPLidar/RPLidarConnection.swift Tests/RPLidarConnectionFixtureTests.swift -o /tmp/rplidar-connection-tests
import Foundation
import Darwin

enum ConnectionFixtureFailure: Error {
    case failed(String)
}

@main
struct RPLidarConnectionFixtureTests {
    static func main() throws {
        try invalidAddresses()
        try repeatedConnections()
        try boundedUnavailableConnection()
        try retryScheduling()
        print("RPLidar connection fixtures passed (1,000 probes, no descriptor growth)")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw ConnectionFixtureFailure.failed(message) }
    }

    static func invalidAddresses() throws {
        for host in ["", "  ", "lidar.invalid", "999.168.11.1", "192.168.11.1:1445", "127.0.0.1\0invalid"] {
            do {
                try RPLidarEndpoint(host: host).checkReachability()
                throw ConnectionFixtureFailure.failed("Accepted invalid address \(host)")
            } catch RPLidarConnectionError.invalidIPAddress {
                // Reject before opening a socket or entering Slamware.
            }
        }
        try expect(RPLidarEndpoint(host: " 192.168.11.1\n").host == "192.168.11.1", "IP was not trimmed")
    }

    static func repeatedConnections() throws {
        let server = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        try expect(server >= 0, "Could not create fixture socket")
        defer { close(server) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(server, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        try expect(bound == 0, "Could not bind fixture socket")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(server, $0, &length)
            }
        }
        try expect(named == 0, "Could not read fixture port")
        let endpoint = RPLidarEndpoint(host: "127.0.0.1", port: UInt16(bigEndian: address.sin_port))
        let baseline = openDescriptorCount()

        // Bound but not listening: deterministic connection refusal.
        for _ in 0..<500 {
            do {
                try endpoint.checkReachability(timeout: 0.1)
                throw ConnectionFixtureFailure.failed("A closed service port was considered reachable")
            } catch RPLidarConnectionError.unreachable {
            }
        }
        try expect(openDescriptorCount() == baseline, "Failed probes leaked descriptors")

        // The same endpoint becomes available without restarting the caller.
        try expect(listen(server, 16) == 0, "Could not listen on fixture socket")
        for _ in 0..<500 {
            try endpoint.checkReachability(timeout: 0.1)
            let connection = accept(server, nil, nil)
            try expect(connection >= 0, "Reachable probe never connected")
            close(connection)
        }
        try expect(openDescriptorCount() == baseline, "Successful probes leaked descriptors")
    }

    static func boundedUnavailableConnection() throws {
        let baseline = openDescriptorCount()
        let start = ProcessInfo.processInfo.systemUptime
        do {
            try RPLidarEndpoint(host: "192.0.2.1").checkReachability(timeout: 0.1)
            throw ConnectionFixtureFailure.failed("Unexpected service on the documentation-only address")
        } catch RPLidarConnectionError.unreachable {
        }
        try expect(ProcessInfo.processInfo.systemUptime - start < 1, "Unavailable check exceeded its deadline")
        try expect(openDescriptorCount() == baseline, "Timed-out probe leaked a descriptor")
    }

    static func retryScheduling() throws {
        let queue = DispatchQueue(label: "rplidar.connection.fixtures")
        let scheduler = RPLidarRetryScheduler(queue: queue)
        let fired = DispatchSemaphore(value: 0)
        var attempts = 0
        queue.sync {
            // Simulate repeated polling while a reconnect is pending.
            for _ in 0..<100 {
                scheduler.schedule(after: 0.05) {
                    attempts += 1
                    fired.signal()
                }
            }
        }
        try expect(queue.sync { scheduler.isScheduled }, "Retry was not marked pending")
        try expect(fired.wait(timeout: .now() + 2) == .success, "Scheduled retry did not run")
        try expect(queue.sync { attempts == 1 && !scheduler.isScheduled }, "Polling queued duplicate retries")

        let completed = DispatchSemaphore(value: 0)
        queue.sync {
            scheduler.schedule(after: 0.02) { attempts += 100 }
            scheduler.cancel()
            scheduler.schedule(after: 0.05) {
                attempts += 1
                completed.signal()
            }
        }
        try expect(completed.wait(timeout: .now() + 2) == .success, "New retry was lost after cancellation")
        try expect(queue.sync { attempts == 2 && !scheduler.isScheduled }, "Cancelled retry ran after reconnect/stop")
    }

    static func openDescriptorCount() -> Int {
        (0..<getdtablesize()).reduce(into: 0) { count, descriptor in
            if fcntl(descriptor, F_GETFD) != -1 { count += 1 }
        }
    }
}
