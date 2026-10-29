import AppKit
import Darwin
import Foundation
import OSLog
import QuartzCore

private let logger = Logger(subsystem: "io.github.iamrobertorodriguez.DesktopOverlay", category: "runtime")

// Configuration is optional. Without it, the original wallpaper.jpg/png/etc. behavior is used.
private struct OverlayConfig: Decodable, Equatable {
    var mode: String = "static"             // "static" or "solar"
    var latitude: Double? = nil             // Decimal degrees, north positive
    var longitude: Double? = nil            // Decimal degrees, east positive
    var wallpaperSet: String = "The Desert" // Folder under dynamic/
    var crossfadeSeconds: Double = 1.5
    var testDateTime: String? = nil  // Optional ISO 8601 UTC test clock; omit for live sun

    enum CodingKeys: String, CodingKey {
        case mode, latitude, longitude, wallpaperSet, crossfadeSeconds, testDateTime
    }

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "static"
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        wallpaperSet = try c.decodeIfPresent(String.self, forKey: .wallpaperSet) ?? "The Desert"
        crossfadeSeconds = try c.decodeIfPresent(Double.self, forKey: .crossfadeSeconds) ?? 1.5
        testDateTime = try c.decodeIfPresent(String.self, forKey: .testDateTime)
    }
}

private final class SingleInstanceLock {
    private let descriptor: Int32
    init() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesktopOverlay-\(getuid()).lock").path
        descriptor = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}

private struct WallpaperSnapshot: Equatable {
    let path: String
    let modified: Date?
    let size: UInt64?
    let inode: UInt64?
}

private final class AspectFillImageView: NSView {
    let image: NSImage
    init(frame: NSRect, image: NSImage) {
        self.image = image
        super.init(frame: frame)
        wantsLayer = true
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Unavailable") }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        let size = image.size
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        let scale = max(bounds.width / size.width, bounds.height / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        let rect = NSRect(x: bounds.midX - fitted.width / 2,
                          y: bounds.midY - fitted.height / 2,
                          width: fitted.width, height: fitted.height)
        image.draw(in: rect, from: NSRect(origin: .zero, size: size),
                   operation: .sourceOver, fraction: 1, respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high])
    }
}

// Approximate NOAA solar position. Uses the Mac's current clock and a configured
// location; no Location Services permission or network request is required.
private enum Solar {
    // Sample around the current day to locate sunrise and sunset, including DST
    // changes (the calculation itself is UTC). Polar day/night have no crossings.
    // Metadata-derived solar anchor points. Frame indices are 1-based, matching
    // ImageIO exports of the original Apple HEIC frames (01.jpg, 02.jpg, ...).
    // This is a nearest-anchor approximation, not Apple's proprietary interpolation.
    private struct Anchor {
        let altitude: Double
        let frame: Int
    }

    private static let landscapeMorning = [
        Anchor(altitude: -25, frame: 2), Anchor(altitude: -9, frame: 3),
        Anchor(altitude: 0, frame: 4), Anchor(altitude: 5, frame: 1),
        Anchor(altitude: 25, frame: 5)
    ]
    private static let landscapeEvening = [
        Anchor(altitude: -25, frame: 2), Anchor(altitude: -9, frame: 8),
        Anchor(altitude: 0, frame: 7), Anchor(altitude: 5, frame: 6),
        Anchor(altitude: 25, frame: 5)
    ]
    private static let gradientMorning = [
        Anchor(altitude: -87.6146, frame: 1), Anchor(altitude: -17.1078, frame: 2),
        Anchor(altitude: -11.1067, frame: 3), Anchor(altitude: -5.3556, frame: 4),
        Anchor(altitude: 0.1877, frame: 5), Anchor(altitude: 6.0427, frame: 6),
        Anchor(altitude: 11.9786, frame: 7), Anchor(altitude: 18.4530, frame: 8),
        Anchor(altitude: 88.4186, frame: 9)
    ]
    private static let gradientEvening = [
        Anchor(altitude: -87.6146, frame: 1), Anchor(altitude: -17.6982, frame: 16),
        Anchor(altitude: -11.1970, frame: 15), Anchor(altitude: -5.4458, frame: 14),
        Anchor(altitude: 0.7510, frame: 13), Anchor(altitude: 6.4451, frame: 12),
        Anchor(altitude: 12.1375, frame: 11), Anchor(altitude: 18.3632, frame: 10),
        Anchor(altitude: 88.4186, frame: 9)
    ]

    // The azimuth is clockwise from true north (east=90, south=180, west=270).
    static func position(at date: Date, latitude: Double, longitude: Double) -> (altitude: Double, azimuth: Double) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let parts = cal.dateComponents([.hour, .minute, .second], from: date)
        let minutes = Double(parts.hour ?? 0) * 60 + Double(parts.minute ?? 0) + Double(parts.second ?? 0) / 60
        let gamma = 2 * Double.pi / 365 * (day - 1 + (minutes / 60 - 12) / 24)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
                               - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let decl = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
                   - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
                   - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        let trueSolarMinutes = (minutes + eqTime + 4 * longitude).truncatingRemainder(dividingBy: 1440)
        let hourAngle = (trueSolarMinutes / 4 - 180) * Double.pi / 180
        let lat = latitude * Double.pi / 180
        let sine = sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(hourAngle)
        let altitude = asin(max(-1, min(1, sine))) * 180 / Double.pi
        let azimuth = (atan2(sin(hourAngle), cos(hourAngle) * sin(lat) - tan(decl) * cos(lat))
                       * 180 / Double.pi + 180 + 360).truncatingRemainder(dividingBy: 360)
        return (altitude, azimuth)
    }

    static func frame(at date: Date, latitude: Double, longitude: Double, wallpaperSet: String) -> Int {
        let sun = position(at: date, latitude: latitude, longitude: longitude)
        let morning = sun.azimuth < 180
        let anchors: [Anchor]
        if wallpaperSet.caseInsensitiveCompare("Solar Gradients") == .orderedSame {
            anchors = morning ? gradientMorning : gradientEvening
        } else {
            anchors = morning ? landscapeMorning : landscapeEvening
        }
        return anchors.min(by: { abs($0.altitude - sun.altitude) < abs($1.altitude - sun.altitude) })?.frame ?? 1
    }

}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let instanceLock: SingleInstanceLock
    private var windows: [NSWindow] = []
    private var activeViews: [ObjectIdentifier: AspectFillImageView] = [:]
    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var setWatcher: DispatchSourceFileSystemObject?
    private var imageWatcher: DispatchSourceFileSystemObject?
    private var watchedSetPath: String?
    private var watchedImagePath: String?
    private var currentSnapshot: WallpaperSnapshot?
    private var currentImage: NSImage?
    private var refreshGeneration = 0
    private var transitionGeneration = 0
    private var refreshTimer: Timer?
    private var configuration = OverlayConfig()

    private lazy var baseDirectory: URL = URL(fileURLWithPath: CommandLine.arguments[0])
        .resolvingSymlinksInPath().deletingLastPathComponent()

    init(instanceLock: SingleInstanceLock) {
        self.instanceLock = instanceLock
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        directoryWatcher = watchDirectory(baseDirectory.path)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,
            selector: #selector(wokeFromSleep), name: NSWorkspace.didWakeNotification, object: nil)
        refresh()
        // Poll once per minute: also detects clock/time-zone changes and missed FS events.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        directoryWatcher?.cancel()
        setWatcher?.cancel()
        imageWatcher?.cancel()
    }

    private func watchDirectory(_ path: String) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
            eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleRefresh() }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func watchImage(_ path: String?) {
        guard path != watchedImagePath else { return }
        imageWatcher?.cancel()
        imageWatcher = nil
        watchedImagePath = path
        guard let path else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke], queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleRefresh() }
        source.setCancelHandler { close(fd) }
        source.resume()
        imageWatcher = source
    }

    private func scheduleRefresh() {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(350)) { [weak self] in
            guard let self, self.refreshGeneration == generation else { return }
            self.refresh()
        }
    }

    private func readConfiguration() -> OverlayConfig {
        let url = baseDirectory.appendingPathComponent("wallpaper-config.json")
        guard let data = try? Data(contentsOf: url) else { return OverlayConfig() }
        do { return try JSONDecoder().decode(OverlayConfig.self, from: data) }
        catch {
            logger.error("Invalid wallpaper-config.json: \(error.localizedDescription, privacy: .public)")
            return configuration // Preserve last valid settings
        }
    }

    private func imageURL(for config: OverlayConfig) -> URL? {
        let fm = FileManager.default
        let extensions = ["jpg", "jpeg", "png", "heic", "tiff", "bmp", "gif", "webp"]
        if config.mode == "solar" {
            guard let lat = config.latitude, let lon = config.longitude,
                  lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon),
                  !config.wallpaperSet.isEmpty,
                  config.wallpaperSet != ".", config.wallpaperSet != "..",
                  !config.wallpaperSet.contains("/") else {
                logger.error("Solar mode requires valid latitude/longitude and a safe wallpaperSet name")
                return nil
            }
            let folder = baseDirectory.appendingPathComponent("Apple Dynamic Wallpapers", isDirectory: true)
                .appendingPathComponent(config.wallpaperSet, isDirectory: true)
            if watchedSetPath != folder.path {
                setWatcher?.cancel()
                setWatcher = watchDirectory(folder.path)
                watchedSetPath = folder.path
            }
            // Developer-only simulated clock. A malformed value is rejected rather
            // than silently showing live time and producing misleading test results.
            let solarDate: Date
            if let override = config.testDateTime {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let parsed = formatter.date(from: override)
                    ?? ISO8601DateFormatter().date(from: override)
                guard let parsed else {
                    logger.error("Invalid testDateTime; use ISO 8601, e.g. 2026-06-21T06:00:00Z")
                    return nil
                }
                solarDate = parsed
            } else {
                solarDate = Date()
            }
            let frame = Solar.frame(at: solarDate, latitude: lat, longitude: lon, wallpaperSet: config.wallpaperSet)
            if config.testDateTime != nil {
                logger.notice("Solar test clock active; selected frame \(frame)")
            }
            for ext in extensions {
                let url = folder.appendingPathComponent(String(format: "%@ - %02d.%@", folder.lastPathComponent, frame, ext))
                if fm.fileExists(atPath: url.path) { return url }
            }
            logger.error("Missing solar frame \(frame) in \(folder.path, privacy: .public)")
            return nil
        }
        setWatcher?.cancel()
        setWatcher = nil
        watchedSetPath = nil
        for ext in extensions {
            let url = baseDirectory.appendingPathComponent("wallpaper.\(ext)")
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private func snapshot(_ url: URL) -> WallpaperSnapshot? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return WallpaperSnapshot(path: url.path,
            modified: attributes[.modificationDate] as? Date,
            size: (attributes[.size] as? NSNumber)?.uint64Value,
            inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value)
    }

    private func refresh() {
        configuration = readConfiguration()
        guard let url = imageURL(for: configuration), let state = snapshot(url) else {
            if currentImage == nil { logger.warning("No wallpaper loaded; waiting for image files") }
            return // Keep last good wallpaper during partial writes/missing frames
        }
        watchImage(url.path)
        guard state != currentSnapshot else { return }
        guard let data = try? Data(contentsOf: url),
              snapshot(url) == state,
              let image = NSImage(data: data), image.isValid else {
            logger.error("Unable to load wallpaper \(url.path, privacy: .public)")
            return
        }
        let seconds = min(10, max(0, configuration.crossfadeSeconds.isFinite ? configuration.crossfadeSeconds : 1.5))
        present(image, fadeSeconds: seconds)
        currentSnapshot = state
        currentImage = image
        logger.notice("Showing \(url.lastPathComponent, privacy: .public)")
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.backgroundColor = .black
        return window
    }

    private func present(_ image: NSImage, fadeSeconds: Double) {
        transitionGeneration &+= 1
        let generation = transitionGeneration
        if windows.count != NSScreen.screens.count {
            windows.forEach { $0.close() }
            windows = NSScreen.screens.map { makeWindow(for: $0) }
            activeViews.removeAll()
        }
        for (index, window) in windows.enumerated() {
            let screen = NSScreen.screens[index]
            window.setFrame(screen.frame, display: true)
            guard let content = window.contentView else { continue }
            // Remove remnants of a previously interrupted transition.
            let old = activeViews[ObjectIdentifier(window)]
            content.subviews.filter { $0 !== old }.forEach { $0.removeFromSuperview() }
            let newView = AspectFillImageView(frame: content.bounds, image: image)
            newView.wantsLayer = true
            newView.autoresizingMask = [.width, .height]
            newView.alphaValue = old == nil || fadeSeconds == 0 ? 1 : 0
            content.addSubview(newView)
            window.orderFront(nil)
            activeViews[ObjectIdentifier(window)] = newView
            guard let old else { continue }
            if fadeSeconds == 0 { old.removeFromSuperview(); continue }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = fadeSeconds
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                newView.animator().alphaValue = 1
            } completionHandler: { [weak self, weak old] in
                guard let self, self.transitionGeneration == generation else { return }
                old?.removeFromSuperview()
            }
        }
    }

    @objc private func wokeFromSleep() {
        logger.info("Mac woke; refreshing solar wallpaper")
        refresh()
    }

    @objc private func screensChanged() {
        logger.info("Display configuration changed")
        windows.forEach { $0.close() }
        windows.removeAll()
        activeViews.removeAll()
        if let currentImage { present(currentImage, fadeSeconds: 0) }
        else { refresh() }
    }
}

// Preserve original detached launch and single-instance behavior.
if !CommandLine.arguments.contains("--background") {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let task = Process()
    task.executableURL = executable
    task.arguments = Array(CommandLine.arguments.dropFirst()) + ["--background"]
    task.standardInput = FileHandle.nullDevice
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    do { try task.run() }
    catch { logger.fault("Could not launch in background: \(error.localizedDescription, privacy: .public)"); exit(1) }
    exit(0)
}

private let lock: SingleInstanceLock
do { lock = try SingleInstanceLock() }
catch { logger.notice("DesktopOverlay already running or unable to lock: \(error.localizedDescription, privacy: .public)"); exit(0) }
let app = NSApplication.shared
private let delegate = AppDelegate(instanceLock: lock)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
