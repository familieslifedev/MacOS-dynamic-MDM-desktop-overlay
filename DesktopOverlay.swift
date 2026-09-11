import AppKit
import Darwin
import Foundation
import OSLog

private let logger = Logger(
    subsystem: "io.github.iamrobertorodriguez.DesktopOverlay",
    category: "runtime"
)

private enum SingleInstanceLockError: Error {
    case alreadyRunning
    case systemError(operation: String, code: Int32)
}

private final class SingleInstanceLock {
    private let fileDescriptor: Int32

    init() throws {
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesktopOverlay-\(getuid()).lock")
        let descriptor = open(
            lockURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )

        guard descriptor >= 0 else {
            throw SingleInstanceLockError.systemError(operation: "open", code: errno)
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let errorCode = errno
            close(descriptor)

            if errorCode == EWOULDBLOCK || errorCode == EAGAIN {
                throw SingleInstanceLockError.alreadyRunning
            }

            throw SingleInstanceLockError.systemError(operation: "flock", code: errorCode)
        }

        fileDescriptor = descriptor
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }
}

private struct WallpaperSnapshot: Equatable {
    let path: String
    let modificationDate: Date?
    let fileSize: UInt64?
    let fileNumber: UInt64?
}

private struct WallpaperAsset {
    let snapshot: WallpaperSnapshot
    let image: NSImage
}

private struct WallpaperWatchTarget: Equatable {
    let path: String
    let fileNumber: UInt64?
}

private final class AspectFillImageView: NSView {
    private let image: NSImage

    init(frame: NSRect, image: NSImage) {
        self.image = image
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override var isOpaque: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else {
            return
        }

        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let scaledSize = NSSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        let imageRect = NSRect(
            x: bounds.midX - (scaledSize.width / 2),
            y: bounds.midY - (scaledSize.height / 2),
            width: scaledSize.width,
            height: scaledSize.height
        )

        image.draw(
            in: imageRect,
            from: NSRect(origin: .zero, size: imageSize),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let retainedInstanceLock: SingleInstanceLock
    private var windows: [NSWindow] = []
    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var wallpaperWatcher: DispatchSourceFileSystemObject?
    private var watchedWallpaperTarget: WallpaperWatchTarget?
    private var currentWallpaper: WallpaperAsset?
    private var refreshGeneration = 0
    private var pendingForcedWallpaperReload = false

    // Automatically resolve the directory where the executable resides
    private lazy var baseDirectory: String = {
        let execURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        return execURL.deletingLastPathComponent().path
    }()

    init(instanceLock: SingleInstanceLock) {
        retainedInstanceLock = instanceLock
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        watchForChanges()

        // React to screen configuration changes (connect/disconnect monitor)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        let hasOverlay = refreshWallpaperIfNeeded()
        if !hasOverlay, directoryWatcher == nil, wallpaperWatcher == nil {
            logger.fault("No wallpaper is loaded and no file watcher could be started")
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshGeneration &+= 1
        directoryWatcher?.cancel()
        wallpaperWatcher?.cancel()
    }

    private func resolveImagePath() -> String? {
        let dir = baseDirectory
        let fm = FileManager.default
        let supported = ["jpg", "jpeg", "png", "heic", "tiff", "bmp", "gif", "webp"]
        for ext in supported {
            let path = "\(dir)/wallpaper.\(ext)"
            if fm.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func resolveWallpaperSnapshot() -> WallpaperSnapshot? {
        guard let path = resolveImagePath() else {
            return nil
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            return WallpaperSnapshot(
                path: path,
                modificationDate: attributes[.modificationDate] as? Date,
                fileSize: (attributes[.size] as? NSNumber)?.uint64Value,
                fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
            )
        } catch {
            logger.error(
                "Unable to inspect wallpaper at \(path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private func loadWallpaper(from snapshot: WallpaperSnapshot) -> WallpaperAsset? {
        let imageData: Data
        do {
            imageData = try Data(contentsOf: URL(fileURLWithPath: snapshot.path))
        } catch {
            logger.error(
                "Unable to read wallpaper at \(snapshot.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }

        guard let latestSnapshot = resolveWallpaperSnapshot(),
              latestSnapshot == snapshot else {
            logger.info("Wallpaper changed while loading; waiting for file activity to settle")
            scheduleWallpaperRefresh(forceReload: true)
            return nil
        }

        guard let image = NSImage(data: imageData),
              image.isValid,
              image.size.width > 0,
              image.size.height > 0 else {
            logger.error("Unable to decode wallpaper at \(snapshot.path, privacy: .public)")
            return nil
        }

        return WallpaperAsset(snapshot: latestSnapshot, image: image)
    }

    @discardableResult
    private func showOverlay(image: NSImage) -> Bool {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            logger.error("No displays are available for the overlay")
            return false
        }

        var replacementWindows: [NSWindow] = []

        for screen in screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )

            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.isOpaque = true
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.backgroundColor = .black

            guard let contentView = window.contentView else {
                window.close()
                replacementWindows.forEach { $0.close() }
                logger.fault("Unable to create an overlay content view")
                return false
            }

            let imageView = AspectFillImageView(frame: contentView.bounds, image: image)
            imageView.autoresizingMask = [.width, .height]
            contentView.addSubview(imageView)

            replacementWindows.append(window)
        }

        replacementWindows.forEach { $0.orderFront(nil) }

        let previousWindows = windows
        windows = replacementWindows
        previousWindows.forEach { $0.close() }

        let displaySummary = screens.map {
            "\($0.localizedName) (\(Int($0.frame.width))x\(Int($0.frame.height)))"
        }.joined(separator: ", ")
        logger.notice("Overlay active on \(displaySummary, privacy: .public)")
        return true
    }

    private func watchForChanges() {
        let dir = baseDirectory
        let fd = open(dir, O_EVTONLY)
        guard fd >= 0 else {
            let errorCode = errno
            logger.error(
                "Unable to watch \(dir, privacy: .public) [errno \(errorCode)]: \(String(cString: strerror(errorCode)), privacy: .public)"
            )
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleWallpaperRefresh()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        directoryWatcher = source
        logger.info("Watching \(dir, privacy: .public) for wallpaper files")
    }

    private func updateWallpaperWatcher(
        for snapshot: WallpaperSnapshot?,
        force: Bool = false
    ) {
        let target = snapshot.map {
            WallpaperWatchTarget(path: $0.path, fileNumber: $0.fileNumber)
        }

        if !force, target == watchedWallpaperTarget {
            return
        }

        wallpaperWatcher?.cancel()
        wallpaperWatcher = nil
        watchedWallpaperTarget = nil

        guard let snapshot, let target else {
            return
        }

        let fd = open(snapshot.path, O_EVTONLY)
        guard fd >= 0 else {
            let errorCode = errno
            logger.error(
                "Unable to watch \(snapshot.path, privacy: .public) [errno \(errorCode)]: \(String(cString: strerror(errorCode)), privacy: .public)"
            )
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleWallpaperRefresh(forceReload: true)
        }
        source.setCancelHandler { close(fd) }
        source.resume()

        wallpaperWatcher = source
        watchedWallpaperTarget = target
        logger.info("Watching \(snapshot.path, privacy: .public) for in-place changes")
    }

    private func scheduleWallpaperRefresh(forceReload: Bool = false) {
        if forceReload {
            pendingForcedWallpaperReload = true
        }

        refreshGeneration &+= 1
        let scheduledGeneration = refreshGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) { [weak self] in
            guard let self, self.refreshGeneration == scheduledGeneration else {
                return
            }

            self.refreshWallpaperIfNeeded()
        }
    }

    @discardableResult
    private func refreshWallpaperIfNeeded() -> Bool {
        let forceReload = pendingForcedWallpaperReload
        pendingForcedWallpaperReload = false

        guard let snapshot = resolveWallpaperSnapshot() else {
            updateWallpaperWatcher(for: nil, force: forceReload)

            if currentWallpaper == nil {
                logger.notice(
                    "No supported wallpaper is available; waiting for one in \(self.baseDirectory, privacy: .public)"
                )
                return false
            }

            logger.warning("No supported wallpaper is available; keeping the current overlay")
            return true
        }

        updateWallpaperWatcher(for: snapshot, force: forceReload)

        guard forceReload || snapshot != currentWallpaper?.snapshot else {
            logger.debug("Ignoring directory change because the wallpaper is unchanged")
            return currentWallpaper != nil
        }

        guard let wallpaper = loadWallpaper(from: snapshot) else {
            if currentWallpaper == nil {
                logger.warning("Wallpaper is not ready; waiting for another file change")
                return false
            }

            logger.error("Wallpaper refresh failed; keeping the current overlay")
            return true
        }

        guard showOverlay(image: wallpaper.image) else {
            logger.error("Unable to replace overlay windows; keeping the current overlay")
            return currentWallpaper != nil
        }

        currentWallpaper = wallpaper
        return true
    }

    @objc private func screensChanged() {
        logger.info("Display configuration changed; rebuilding overlays")

        guard let currentWallpaper else {
            refreshWallpaperIfNeeded()
            return
        }

        showOverlay(image: currentWallpaper.image)
    }
}

// Auto-background: re-launch itself detached so Terminal can close immediately
if !CommandLine.arguments.contains("--background") {
    let execURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let task = Process()
    task.executableURL = execURL
    task.arguments = Array(CommandLine.arguments.dropFirst()) + ["--background"]
    task.standardInput = FileHandle.nullDevice
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    do {
        try task.run()
    } catch {
        logger.fault(
            "Failed to launch in background: \(error.localizedDescription, privacy: .public)"
        )
        exit(1)
    }
    exit(0)
}

private let instanceLock: SingleInstanceLock
do {
    instanceLock = try SingleInstanceLock()
} catch SingleInstanceLockError.alreadyRunning {
    logger.notice("DesktopOverlay is already running; exiting duplicate launch")
    exit(0)
} catch SingleInstanceLockError.systemError(let operation, let code) {
    logger.fault(
        "Unable to acquire the single-instance lock during \(operation, privacy: .public) [errno \(code)]: \(String(cString: strerror(code)), privacy: .public)"
    )
    exit(1)
} catch {
    logger.fault(
        "Unable to acquire the single-instance lock: \(error.localizedDescription, privacy: .public)"
    )
    exit(1)
}

let app = NSApplication.shared
private let delegate = AppDelegate(instanceLock: instanceLock)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
