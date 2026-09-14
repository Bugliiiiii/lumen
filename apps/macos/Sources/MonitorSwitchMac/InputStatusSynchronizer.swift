import Foundation

@MainActor
final class InputStatusSynchronizer {
    private let interval: Duration
    private let refresh: () -> Void
    private var task: Task<Void, Never>?

    init(interval: Duration = .seconds(2), refresh: @escaping () -> Void) {
        self.interval = interval
        self.refresh = refresh
    }

    var isRunning: Bool { task != nil }

    func start() {
        stop()
        refresh()
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                refresh()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
