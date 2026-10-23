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

    enum CodingKeys: String, CodingKey {
        case mode, latitude, longitude, wallpaperSet, crossfadeSeconds
    }

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "static"
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        wallpaperSet = try c.decodeIfPresent(String.self, forKey: .wallpaperSet) ?? "The Desert"
        crossfadeSeconds = try c.decodeIfPresent(Double.self, forKey: .crossfadeSeconds) ?? 1.5
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
    static func elevation(at date: Date, latitude: Double, longitude: Double) -> Double {
        let calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(secondsFromGMT: 0)!
        var cal = calendar
        cal.timeZone = utc
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
        return asin(max(-1, min(1, sine))) * 180 / Double.pi
    }

    // Sample around the current day to locate sunrise and sunset, including DST
    // changes (the calculation itself is UTC). Polar day/night have no crossings.
    static func sunEvents(around date: Date, latitude: Double, longitude: Double) -> (Date, Date)? {
        // Assumes the configured location is in the Mac's local time zone.
        // This is appropriate for a desktop at its usual location.
        let start = Calendar.current.startOfDay(for: date)
        var sunrise: Date?
        var sunset: Date?
        var previous = start
        var previousValue = elevation(at: previous, latitude: latitude, longitude: longitude) + 0.833
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let interval = end.timeIntervalSince(start) / 96
        for step in 1...96 { // local calendar day, including DST transitions
            let next = start.addingTimeInterval(Double(step) * interval)
            let value = elevation(at: next, latitude: latitude, longitude: longitude) + 0.833
            if (previousValue <= 0 && value > 0) || (previousValue >= 0 && value < 0) {
                var low = previous
                var high = next
                for _ in 0..<14 {
                    let mid = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
                    let midValue = elevation(at: mid, latitude: latitude, longitude: longitude) + 0.833
                    if (midValue > 0) == (previousValue > 0) { low = mid } else { high = mid }
                }
                let crossing = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
                if previousValue < 0 { if sunrise == nil { sunrise = crossing } }
                else if sunset == nil { sunset = crossing }
            }
            previous = next
            previousValue = value
        }
        guard let rise = sunrise, let set = sunset, rise < set else { return nil }
        return (rise, set)
    }

    // Eight ordered images: dawn, morning, late morning, midday, afternoon,
    // sunset, dusk, night. These are *assumed* ordering, not HEIC metadata.
    static func frame(at date: Date, latitude: Double, longitude: Double) -> Int {
        guard let (sunrise, sunset) = sunEvents(around: date, latitude: latitude, longitude: longitude) else {
            return elevation(at: date, latitude: latitude, longitude: longitude) > 0 ? 4 : 8
        }
        let dawn = sunrise.addingTimeInterval(-45 * 60)
        let dusk = sunset.addingTimeInterval(45 * 60)
        if date < dawn || date >= dusk { return 8 }
        if date < sunrise { return 1 }
        if date >= sunset { return 7 }
        let fraction = date.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise)
        if fraction < 0.18 { return 2 }
        if fraction < 0.38 { return 3 }
        if fraction < 0.62 { return 4 }
        if fraction < 0.82 { return 5 }
        return 6
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
        let url = baseDirectory.appendingPathComponent("overlay.json")
        guard let data = try? Data(contentsOf: url) else { return OverlayConfig() }
        do { return try JSONDecoder().decode(OverlayConfig.self, from: data) }
        catch {
            logger.error("Invalid overlay.json: \(error.localizedDescription, privacy: .public)")
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
            let folder = baseDirectory.appendingPathComponent("dynamic", isDirectory: true)
                .appendingPathComponent(config.wallpaperSet, isDirectory: true)
            if watchedSetPath != folder.path {
                setWatcher?.cancel()
                setWatcher = watchDirectory(folder.path)
                watchedSetPath = folder.path
            }
            let frame = Solar.frame(at: Date(), latitude: lat, longitude: lon)
            for ext in extensions {
                let url = folder.appendingPathComponent(String(format: "%02d.%@", frame, ext))
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

let lock: SingleInstanceLock
do { lock = try SingleInstanceLock() }
catch { logger.notice("DesktopOverlay already running or unable to lock: \(error.localizedDescription, privacy: .public)"); exit(0) }
let app = NSApplication.shared
let delegate = AppDelegate(instanceLock: lock)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
