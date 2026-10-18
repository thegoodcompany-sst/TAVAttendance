import Network
import SwiftUI

final class NetworkMonitor: ObservableObject {
    @Published var isConnected = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                // Demo mode never needs the network, so it always behaves as online
                // (no offline queue) even in airplane mode.
                self?.isConnected = DemoMode.isActive || path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }

    deinit { monitor.cancel() }
}
