import CoreServices
import Foundation

/// Recursive FSEvents watcher on a content root. Each coalesced change
/// calls `handler` on an arbitrary queue — hop to the main actor before
/// touching the coordinator.
final class ContentTreeWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "dev.drawmeanelephant.solipsist.content-watch")
    var handler: (@Sendable () -> Void)?

    deinit { stop() }

    func start(path: String) {
        stop()
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<ContentTreeWatcher>.fromOpaque(info).takeUnretainedValue().handler?()
        }
        guard let created = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot
            )
        ) else { return }
        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
