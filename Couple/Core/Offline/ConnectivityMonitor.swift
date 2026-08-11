import Foundation
import Network

final class ConnectivityMonitor: @unchecked Sendable {
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    init() {
        monitor = NWPathMonitor()
        queue = DispatchQueue(label: "com.oursince.couple.connectivity")
    }

    func statusStream() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { [monitor] _ in monitor.cancel() }
            monitor.start(queue: queue)
        }
    }

    func cancel() {
        monitor.cancel()
    }
}
