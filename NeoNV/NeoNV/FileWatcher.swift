import Foundation
import CoreServices

enum FileChangeEvent {
    case created(URL)
    case modified(URL)
    case deleted(URL)
    case renamed(oldURL: URL?, newURL: URL?)
}

@MainActor
protocol FileWatcherDelegate: AnyObject {
    func fileWatcher(_ watcher: FileWatcher, didObserveChanges events: [FileChangeEvent])
}

final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let path: String
    private let debounceInterval: TimeInterval
    private var pendingEvents: [(String, FSEventStreamEventFlags)] = []
    private var debounceTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.neonv.filewatcher", qos: .utility)
    
    weak var delegate: FileWatcherDelegate?
    
    private let allowedExtensions: Set<String> = ["txt", "md", "markdown", "org", "text"]
    
    init(path: String, debounceInterval: TimeInterval = 0.15) {
        self.path = path
        self.debounceInterval = debounceInterval
    }
    
    deinit {
        stop()
    }
    
    func start() {
        guard stream == nil else { return }
        
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let flags: FSEventStreamCreateFlags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )
        
        let pathsToWatch = [path] as CFArray
        
        stream = FSEventStreamCreate(
            nil,
            { (_, clientCallbackInfo, numEvents, eventPaths, eventFlags, _) in
                guard let clientCallbackInfo = clientCallbackInfo else { return }
                let watcher = Unmanaged<FileWatcher>.fromOpaque(clientCallbackInfo).takeUnretainedValue()
                
                guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
                let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))
                
                watcher.handleRawEvents(paths: paths, flags: flags)
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1,
            flags
        )
        
        guard let stream = stream else { return }
        
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }
    
    func stop() {
        debounceTimer?.cancel()
        debounceTimer = nil
        
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
    
    private func handleRawEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            for (path, flag) in zip(paths, flags) {
                self.pendingEvents.append((path, flag))
            }
            
            self.scheduleDebounce()
        }
    }
    
    private func scheduleDebounce() {
        debounceTimer?.cancel()
        
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + debounceInterval)
        timer.setEventHandler { [weak self] in
            self?.processPendingEvents()
        }
        timer.resume()
        debounceTimer = timer
    }
    
    private func processPendingEvents() {
        let events = pendingEvents
        pendingEvents = []
        
        var changeEvents: [FileChangeEvent] = []
        var seenPaths = Set<String>()
        
        for (path, flags) in events {
            guard !seenPaths.contains(path) else { continue }
            seenPaths.insert(path)
            
            let url = URL(fileURLWithPath: path)
            let ext = url.pathExtension.lowercased()
            
            guard allowedExtensions.contains(ext) || isDirectory(path) else { continue }
            
            if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
                changeEvents.append(.deleted(url))
            } else if flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
                if FileManager.default.fileExists(atPath: path) {
                    changeEvents.append(.created(url))
                } else {
                    changeEvents.append(.deleted(url))
                }
            } else if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
                if allowedExtensions.contains(ext) {
                    changeEvents.append(.created(url))
                }
            } else if flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 {
                if allowedExtensions.contains(ext) {
                    changeEvents.append(.modified(url))
                }
            } else if flags & UInt32(kFSEventStreamEventFlagItemInodeMetaMod) != 0 {
                // Metadata-only changes (xattrs, permissions) are commonly triggered
                // by cloud sync services. Skip these — content hash check in NoteStore
                // handles the rare case where content actually changed.
                continue
            }
        }
        
        guard !changeEvents.isEmpty else { return }
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.delegate?.fileWatcher(self, didObserveChanges: changeEvents)
        }
    }
    
    private func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
