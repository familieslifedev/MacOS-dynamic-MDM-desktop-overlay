import SwiftUI
import AppKit
import Foundation
import Darwin
import ServiceManagement

@MainActor
final class Manager: ObservableObject {
    @Published var selectedSet = ""
    @Published var sets: [String] = []
    @Published var status = "Checking…"
    @Published var detail = ""
    @Published var busy = false
    @Published var testMode = false
    @Published var customDate = Date()
    @Published var crossfadeSeconds: Double = 1.5
    @Published var clockNow = Date()
    @Published var tab = 0
    @Published var previewFrame = 1
    @Published var showingSetup = false
    @Published var setupStep = 0
    @Published var setupSet = ""
    @Published var setupSolar = true
    @Published var setupLatitude = ""
    @Published var setupLongitude = ""
    @Published var setupFade = 1.5
    @Published var setupStart = true
    @Published var setupError = ""
    @Published var setupInfo = ""
    private var clockTimer: Timer?
    @Published var launchAtLogin = false
    @Published var autoStartOverlay = false
    @Published var autoRecover = false
    @Published var diagnostics = ""
    @Published var validationIssues: [String] = []
    @Published var recentEvents: [String] = []
    private var deliberateStop = false
    private var previouslyRunning = false
    private var recoveryAttempts = 0
    private var lastRecovery = Date.distantPast
    private var wakeObserver: NSObjectProtocol?
    private let preferences = UserDefaults.standard

    private func record(_ message: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        recentEvents.insert("[\(time)] \(message)", at: 0)
        if recentEvents.count > 30 { recentEvents.removeLast() }
    }


    var effectiveSolarTime: Date { testMode ? customDate : clockNow }
    var currentModeLabel: String { testMode ? "Simulated solar time" : "Live solar time" }
    var currentPreviewURL: URL? {
        let folder = images.appendingPathComponent(selectedSet, isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }.first
    }

    // Preview is intentionally manual: it never changes the live overlay or configuration.
    var previewFrameCount: Int { selectedSet == "Solar Gradients" ? 16 : 8 }
    var selectedFrameURL: URL? {
        guard !selectedSet.isEmpty else { return nil }
        let folder = images.appendingPathComponent(selectedSet, isDirectory: true)
        let stem = String(format: "%@ - %02d", selectedSet, previewFrame)
        for ext in ["jpg", "jpeg", "png", "heic"] {
            let url = folder.appendingPathComponent("\(stem).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
    func movePreview(_ delta: Int) {
        let count = previewFrameCount
        previewFrame = ((previewFrame - 1 + delta % count + count) % count) + 1
    }

    func startClock() {
        guard clockTimer == nil else { return }
        clockNow = Date()
        checkHealth()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.clockNow = Date()
                self?.reload()
                self?.checkHealth()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.record("Mac woke from sleep; checking overlay")
                self?.reload()
                self?.checkHealth()
                // The overlay's timer will select the current solar frame.
            }
        }
    }

    func stopClock() {
        clockTimer?.invalidate(); clockTimer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    func updateCrossfade(_ seconds: Double) {
        do {
            let data = try Data(contentsOf: config)
            guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "Manager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Configuration must be a JSON object"])
            }
            let value = (seconds * 10).rounded() / 10
            json["crossfadeSeconds"] = value
            let updated = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try updated.write(to: config, options: .atomic)
            crossfadeSeconds = value
            detail = "Crossfade set to \(String(format: "%.1f", value)) seconds. Applies to the next image change."
        } catch { detail = "Crossfade setting failed: \(error.localizedDescription)" }
    }

    // Bundle lives at <repository>/DynamicDesktopManager.app/Contents/MacOS/...
    private var repo: URL {
        Bundle.main.bundleURL.deletingLastPathComponent()
    }
    private var executable: URL { repo.appendingPathComponent("DesktopOverlayDynamic") }
    private var config: URL { repo.appendingPathComponent("wallpaper-config.json") }
    private var images: URL { repo.appendingPathComponent("Apple Dynamic Wallpapers", isDirectory: true) }

    init() {
        autoStartOverlay = preferences.bool(forKey: "autoStartOverlay")
        autoRecover = preferences.bool(forKey: "autoRecover")
        launchAtLogin = SMAppService.mainApp.status == .enabled
        reload()
        previouslyRunning = !runningPIDs().isEmpty
        let configurationExists = FileManager.default.fileExists(atPath: config.path)
        let validConfiguration = (try? Data(contentsOf: config)).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        } != nil
        if !configurationExists || !validConfiguration {
            beginSetup()
        } else if autoStartOverlay && !previouslyRunning {
            launchOverlay(reason: "Automatic startup")
        }
    }

    // First-run wizard. Existing settings are read, but never changed until Finish.
    func beginSetup() {
        reload()
        let existing = (try? Data(contentsOf: config)).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        } ?? [:]
        setupSet = (existing["wallpaperSet"] as? String).flatMap { sets.contains($0) ? $0 : nil } ?? (sets.first ?? "")
        setupSolar = (existing["mode"] as? String ?? "solar") == "solar"
        setupLatitude = (existing["latitude"] as? NSNumber).map { $0.stringValue } ?? ""
        setupLongitude = (existing["longitude"] as? NSNumber).map { $0.stringValue } ?? ""
        setupFade = min(10, max(0, (existing["crossfadeSeconds"] as? NSNumber)?.doubleValue ?? 1.5))
        setupStart = true
        setupError = ""
        setupInfo = ""
        setupStep = 0
        showingSetup = true
    }

    func cancelSetup() {
        showingSetup = false
        setupError = ""
    }

    // Import only a complete, correctly named frame collection. Never overwrite.
    func importWallpaperCollection() {
        let panel = NSOpenPanel()
        panel.title = "Choose a wallpaper collection folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let name = source.lastPathComponent
        let expected = (name == "Solar Gradients") ? 16 : 8
        let fm = FileManager.default
        let destination = images.appendingPathComponent(name, isDirectory: true)
        do {
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
                throw setupFailure("Invalid folder name.")
            }
            guard !fm.fileExists(atPath: destination.path) else {
                throw setupFailure("A collection with that name already exists. Rename the source folder first.")
            }
            let contents = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            for index in 1...expected {
                let stem = String(format: "%@ - %02d", name, index)
                guard contents.contains(where: { $0.deletingPathExtension().lastPathComponent == stem &&
                    ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }) else {
                    throw setupFailure("Missing frame \(stem). Expected \(expected) numbered frames.")
                }
            }
            try fm.createDirectory(at: images, withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: destination)
            reload()
            setupSet = name
            setupInfo = "Imported \(name) successfully."
            setupError = ""
            record("Wallpaper collection imported")
        } catch {
            setupError = "Import failed: \(error.localizedDescription)"
        }
    }

    private func setupFailure(_ message: String) -> NSError {
        NSError(domain: "DynamicDesktopSetup", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    var setupValidation: String? {
        guard sets.contains(setupSet) else { return "Choose or import a wallpaper collection." }
        if !setupSolar {
            let staticImage = ["jpg", "jpeg", "png", "heic", "tiff", "bmp", "gif", "webp"].contains {
                FileManager.default.fileExists(atPath: repo.appendingPathComponent("wallpaper.\($0)").path)
            }
            guard staticImage else { return "Static mode requires a wallpaper.jpg (or other supported wallpaper file) in the repository." }
        }
        if setupSolar {
            guard let lat = Double(setupLatitude.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let lon = Double(setupLongitude.trimmingCharacters(in: .whitespacesAndNewlines)),
                  lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon) else {
                return "Enter valid latitude (-90 to 90) and longitude (-180 to 180)."
            }
        }
        guard setupFade.isFinite, (0...10).contains(setupFade) else { return "Invalid crossfade duration." }
        return nil
    }

    func finishSetup() {
        guard let error = setupValidation else {
            do {
                // Preserve unrelated keys in an existing config, including private values.
                let existing = (try? Data(contentsOf: config)).flatMap {
                    try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
                } ?? [:]
                var updated = existing
                updated["mode"] = setupSolar ? "solar" : "static"
                updated["wallpaperSet"] = setupSet
                updated["crossfadeSeconds"] = setupFade
                if setupSolar {
                    updated["latitude"] = Double(setupLatitude.trimmingCharacters(in: .whitespacesAndNewlines))!
                    updated["longitude"] = Double(setupLongitude.trimmingCharacters(in: .whitespacesAndNewlines))!
                }
                // The setup wizard always returns to the live clock.
                updated.removeValue(forKey: "testDateTime")
                let data = try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: config, options: .atomic)
                showingSetup = false
                reload()
                checkHealth()
                detail = "Setup saved. \(setupSolar ? "Solar" : "Static") mode configured."
                record("Setup completed")
                if setupStart { restart() }
            } catch {
                setupError = "Could not save configuration: \(error.localizedDescription)"
            }
            return
        }
        setupError = error
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            record("Launch at login: \(launchAtLogin ? "enabled" : "disabled")")
            if enabled && !launchAtLogin {
                detail = "macOS has not enabled login startup. Check System Settings → General → Login Items."
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            detail = "Launch at login failed: \(error.localizedDescription). An unsigned development app may need signing."
            record("Login item registration failed")
        }
    }

    func setAutoStart(_ enabled: Bool) {
        autoStartOverlay = enabled
        preferences.set(enabled, forKey: "autoStartOverlay")
        record("Auto-start overlay \(enabled ? "enabled" : "disabled")")
    }

    func setAutoRecover(_ enabled: Bool) {
        autoRecover = enabled
        preferences.set(enabled, forKey: "autoRecover")
        record("Crash recovery \(enabled ? "enabled" : "disabled")")
    }

    private func launchOverlay(reason: String) {
        guard runningPIDs().isEmpty else { return }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            detail = "Overlay executable missing. Build it first."
            record("Launch skipped: executable missing")
            return
        }
        do {
            let task = Process()
            task.executableURL = executable
            task.currentDirectoryURL = repo
            try task.run()
            deliberateStop = false
            record(reason)
        } catch {
            detail = "Overlay launch failed: \(error.localizedDescription)"
            record("Launch failed")
        }
    }

    private func checkHealth() {
        let running = !runningPIDs().isEmpty
        if running {
            if !previouslyRunning { record("Overlay running") }
            recoveryAttempts = 0
        } else if previouslyRunning && !deliberateStop {
            record("Overlay exited unexpectedly")
        }
        if !running && autoRecover && !deliberateStop && previouslyRunning && !busy {
            // At most three recovery attempts within a rolling 5-minute window.
            if Date().timeIntervalSince(lastRecovery) > 300 { recoveryAttempts = 0 }
            if recoveryAttempts < 3 {
                recoveryAttempts += 1
                lastRecovery = Date()
                launchOverlay(reason: "Recovery attempt \(recoveryAttempts)/3")
            } else {
                detail = "Auto-recovery paused after repeated exits. Restart manually."
            }
        }
        previouslyRunning = !runningPIDs().isEmpty || (autoRecover && !deliberateStop && recoveryAttempts > 0)
        validateInstallation()
    }

    // Shared contract with DesktopOverlay.swift: mode, coordinates, set, fade and test clock.
    // Diagnostics deliberately omit coordinates and filesystem paths.
    func validateInstallation() {
        var issues: [String] = []
        let fm = FileManager.default
        if !fm.isExecutableFile(atPath: executable.path) {
            issues.append("Overlay executable is missing or not executable. Use Build.")
        }
        guard let data = try? Data(contentsOf: config) else {
            issues.append("Configuration missing. Run Setup Assistant.")
            validationIssues = issues
            diagnostics = "Configuration: Missing\nOverlay: \(runningPIDs().isEmpty ? "Stopped" : "Running")\nIssues: \(issues.count)"
            return
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            issues.append("Configuration is not a JSON object. Run Setup Assistant.")
            validationIssues = issues
            diagnostics = "Configuration: Invalid JSON\nIssues: \(issues.count)"
            return
        }
        let mode = json["mode"] as? String ?? "static"
        let set = json["wallpaperSet"] as? String ?? "The Desert"
        if mode != "solar" && mode != "static" { issues.append("Mode must be solar or static.") }
        if let fade = (json["crossfadeSeconds"] as? NSNumber)?.doubleValue,
           (!fade.isFinite || !(0...10).contains(fade)) { issues.append("Crossfade must be between 0 and 10 seconds.") }
        if let override = json["testDateTime"] as? String,
           ISO8601DateFormatter().date(from: override) == nil {
            issues.append("Simulated solar time is invalid. Return to Live Solar.")
        }
        var count = 0
        if mode == "solar" {
            let lat = (json["latitude"] as? NSNumber)?.doubleValue
            let lon = (json["longitude"] as? NSNumber)?.doubleValue
            if lat == nil || lon == nil || !lat!.isFinite || !lon!.isFinite || !(-90...90).contains(lat!) || !(-180...180).contains(lon!) {
                issues.append("Solar coordinates are missing or invalid. Run Setup Assistant.")
            }
            if set.isEmpty || set == "." || set == ".." || set.contains("/") || set.contains("\\") {
                issues.append("Wallpaper collection name is unsafe or empty.")
            } else {
                let folder = images.appendingPathComponent(set, isDirectory: true)
                let expected = set.caseInsensitiveCompare("Solar Gradients") == .orderedSame ? 16 : 8
                let contents = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
                for index in 1...expected {
                    let stem = String(format: "%@ - %02d", set, index)
                    if contents.contains(where: { $0.deletingPathExtension().lastPathComponent == stem &&
                        ["jpg", "jpeg", "png", "heic", "tiff", "bmp", "gif", "webp"].contains($0.pathExtension.lowercased()) }) {
                        count += 1
                    }
                }
                if count != expected { issues.append("Wallpaper frames: \(count) of \(expected) found.") }
            }
        } else if mode == "static" {
            if !["jpg", "jpeg", "png", "heic", "tiff", "bmp", "gif", "webp"].contains(where: {
                fm.fileExists(atPath: repo.appendingPathComponent("wallpaper.\($0)").path)
            }) { issues.append("Static wallpaper image is missing.") }
        }
        validationIssues = issues
        diagnostics = "Overlay: \(runningPIDs().isEmpty ? "Stopped" : "Running") | Config: Parsed\nMode: \(mode) | Set: \(set) | Frames: \(count)\nSimulation: \(json["testDateTime"] == nil ? "Off" : "On") | Recovery: \(autoRecover ? "On" : "Off")\nIssues: \(issues.count)"
    }

    func exportDiagnostics() {
        validateInstallation()
        let panel = NSSavePanel()
        panel.title = "Export redacted diagnostics"
        panel.nameFieldStringValue = "DynamicDesktop-diagnostics.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Do not export raw configuration, coordinates, absolute paths or event details.
        let report = "Dynamic Desktop Manager v0.9\nGenerated: \(Date().formatted())\n\n\(diagnostics)\n\nValidation findings:\n" +
            (validationIssues.isEmpty ? "None" : validationIssues.joined(separator: "\n")) + "\n"
        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
            detail = "Redacted diagnostics exported."
            record("Diagnostics exported")
        } catch { detail = "Export failed: \(error.localizedDescription)" }
    }

    func repairSimulatedTime() {
        returnToLive()
        validateInstallation()
    }



    func reload() {
        sets = ((try? FileManager.default.contentsOfDirectory(at: images, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent).sorted()
        if let data = try? Data(contentsOf: config),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = json["wallpaperSet"] as? String { selectedSet = name }
        if let data = try? Data(contentsOf: config),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let value = json["testDateTime"] as? String,
               let date = Self.isoFormatter.date(from: value) {
                testMode = true
                customDate = date
            } else {
                testMode = false
            }
        }
        if let data = try? Data(contentsOf: config),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let seconds = json["crossfadeSeconds"] as? Double, seconds.isFinite {
            crossfadeSeconds = min(10, max(0, seconds))
        }
        status = runningPIDs().isEmpty ? "Stopped" : "Running"
    }

    func choose(_ name: String) {
        guard sets.contains(name) else { return }
        do {
            let data = try Data(contentsOf: config)
            guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "Manager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Configuration must be a JSON object"])
            }
            json["wallpaperSet"] = name
            let updated = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try updated.write(to: config, options: .atomic)
            selectedSet = name
            previewFrame = 1
            detail = "Selected \(name). The overlay will refresh automatically."
        } catch { detail = "Configuration error: \(error.localizedDescription)" }
    }

    private static var isoFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    private func updateTestDate(_ date: Date?) {
        do {
            let data = try Data(contentsOf: config)
            guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "Manager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Configuration must be a JSON object"])
            }
            if let date {
                json["testDateTime"] = Self.isoFormatter.string(from: date)
            } else {
                json.removeValue(forKey: "testDateTime")
            }
            let updated = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try updated.write(to: config, options: .atomic)
            testMode = date != nil
            if let date { customDate = date }
            detail = date == nil ? "Live solar time restored." : "Simulated time saved. Overlay will refresh automatically."
        } catch {
            detail = "Solar test configuration error: \(error.localizedDescription)"
        }
    }

    func simulate(hour: Int, month: Int = 6, day: Int = 21) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = DateComponents(year: 2026, month: month, day: day, hour: hour, minute: 0)
        guard let date = calendar.date(from: components) else { return }
        updateTestDate(date)
    }

    func applyCustomDate() { updateTestDate(customDate) }
    func returnToLive() { updateTestDate(nil) }

    private func runningPIDs() -> [pid_t] {
        let target = executable.resolvingSymlinksInPath().path
        let max = 4096
        var pids = [pid_t](repeating: 0, count: max)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(max * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return [] }
        return pids.prefix(Int(bytes) / MemoryLayout<pid_t>.size).filter { pid in
            guard pid > 0, pid != getpid() else { return false }
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
            return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath().path == target
        }
    }

    private func stopProcesses() async {
        for pid in runningPIDs() { _ = Darwin.kill(pid, SIGTERM) }
        for _ in 0..<30 {
            if runningPIDs().isEmpty { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func stop() {
        guard !busy else { return }
        busy = true
        deliberateStop = true
        Task {
            await stopProcesses()
            busy = false
            reload()
            detail = runningPIDs().isEmpty ? "Overlay stopped." : "Overlay did not stop within 3 seconds."
            record(detail)
        }
    }

    func restart() {
        guard !busy else { return }
        busy = true
        deliberateStop = true
        Task {
            await stopProcesses()
            guard runningPIDs().isEmpty else {
                detail = "Overlay did not stop; not starting a duplicate."
                busy = false; reload(); return
            }
            do {
                guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                    throw NSError(domain: "Manager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Build the overlay first."])
                }
                let task = Process()
                task.executableURL = executable
                task.currentDirectoryURL = repo
                try task.run()
                deliberateStop = false
                previouslyRunning = true
                record("Overlay restarted")
                detail = "Overlay launched."
            } catch { detail = "Restart failed: \(error.localizedDescription)" }
            busy = false
            reload()
        }
    }

    func build(andRestart: Bool = false) {
        guard !busy else { return }
        busy = true
        status = "Building…"
        detail = "Compiling DesktopOverlay.swift…"
        let folder = repo
        Task.detached {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            task.arguments = ["swiftc", "-O", "-framework", "AppKit", "-framework", "QuartzCore", "DesktopOverlay.swift", "-o", "DesktopOverlayDynamic.next"]
            task.currentDirectoryURL = folder
            let output = Pipe()
            task.standardOutput = output
            task.standardError = output
            do {
                try task.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                let log = String(data: data, encoding: .utf8) ?? "(Unable to decode compiler output)"
                await MainActor.run {
                    if task.terminationStatus == 0 {
                        do {
                            let staged = folder.appendingPathComponent("DesktopOverlayDynamic.next")
                            let final = folder.appendingPathComponent("DesktopOverlayDynamic")
                            // Rename over the previous executable atomically; running process keeps old image.
                            let result = rename(staged.path, final.path)
                            guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                            self.detail = "Build succeeded."
                            self.busy = false
                            self.reload()
                            if andRestart { self.restart() }
                        } catch { self.detail = "Build succeeded, install failed: \(error.localizedDescription)"; self.busy = false; self.reload() }
                    } else {
                        self.detail = "Build failed (exit \(task.terminationStatus)):\n\(String(log.suffix(3500)))"
                        self.busy = false
                        self.reload()
                    }
                }
            } catch {
                await MainActor.run { self.detail = "Build failed: \(error.localizedDescription)"; self.busy = false; self.reload() }
            }
        }
    }
}

struct ManagerView: View {
    @StateObject private var manager = Manager()
    var body: some View {
        ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 12) {
            if manager.showingSetup {
                setupWizard
            } else {
            HStack {
                Text("Dynamic Desktop Manager").font(.headline)
                Spacer()
                Label(manager.status, systemImage: manager.status == "Running" ? "checkmark.circle.fill" : "pause.circle")
                    .font(.caption).foregroundStyle(manager.status == "Running" ? .green : .secondary)
            }
            // Explicit button actions avoid Picker selection issues in MenuBarExtra windows.
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Button {
                        manager.tab = index
                    } label: {
                        Text(["Wallpaper", "Testing", "System"][index])
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(manager.tab == index ? Color.accentColor.opacity(0.20) : Color.secondary.opacity(0.07))
                            .cornerRadius(7)
                    }
                    .buttonStyle(.plain)
                }
            }
            if manager.tab == 0 {
            HStack {
                Text("Wallpaper set")
                Spacer()
                Menu {
                    ForEach(manager.sets, id: \.self) { name in
                        Button {
                            manager.choose(name)
                            manager.previewFrame = 1
                        } label: {
                            if name == manager.selectedSet {
                                Label(name, systemImage: "checkmark")
                            } else {
                                Text(name)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(manager.selectedSet.isEmpty ? "Choose collection" : manager.selectedSet)
                        Image(systemName: "chevron.up.chevron.down")
                    }
                }
                .disabled(manager.sets.isEmpty || manager.busy)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Wallpaper gallery", systemImage: "photo.on.rectangle.angled")
                        .font(.subheadline).bold()
                    Spacer()
                    Text("Frame \(manager.previewFrame) of \(manager.previewFrameCount)")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                if let url = manager.selectedFrameURL, let preview = NSImage(contentsOf: url) {
                    Image(nsImage: preview)
                        .resizable().scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 195)
                        .clipped().cornerRadius(10)
                        // A scaledToFill image can retain an oversized hit-test region
                        // outside its visible clipped frame. It must not intercept controls.
                        .allowsHitTesting(false)
                        .accessibilityLabel("Wallpaper preview frame \(manager.previewFrame)")
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.10))
                        VStack(spacing: 6) {
                            Image(systemName: "photo.badge.exclamationmark").font(.title2)
                            Text("Frame not available").font(.caption)
                        }.foregroundStyle(.secondary)
                    }.frame(height: 165)
                }
                HStack {
                    Button { manager.movePreview(-1) } label: { Label("Previous", systemImage: "chevron.left") }
                    Spacer()
                    Text(manager.selectedSet).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button { manager.movePreview(1) } label: { Label("Next", systemImage: "chevron.right") }
                }.disabled(manager.sets.isEmpty)
                Text("Gallery previews are manual and do not change the desktop wallpaper.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(12)
            Divider()
            HStack {
                Text("Solar information").font(.headline)
                Spacer()
                Text(manager.currentModeLabel).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("Solar clock")
                Spacer()
                Text(manager.effectiveSolarTime.formatted(date: .abbreviated, time: .shortened))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Text("The overlay calculates solar position and frame selection independently. This panel shows its configured clock, not the computed frame.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Text("Crossfade duration").font(.headline)
                Spacer()
                Text(String(format: "%.1f s", manager.crossfadeSeconds)).monospacedDigit()
            }
            Slider(value: Binding(
                get: { manager.crossfadeSeconds },
                set: { manager.crossfadeSeconds = $0 }
            ), in: 0...10, step: 0.5, onEditingChanged: { editing in
                if !editing { manager.updateCrossfade(manager.crossfadeSeconds) }
            }).disabled(manager.busy)
            Text("Changes apply on the next wallpaper transition.")
                .font(.caption2).foregroundStyle(.secondary)
            }
            if manager.tab == 1 {
            Divider()
            HStack {
                Text("Solar Testing").font(.headline)
                Spacer()
                if manager.testMode {
                    Text("TEST MODE").font(.caption2).bold().foregroundStyle(.orange)
                } else {
                    Text("Live solar").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Sunrise") { manager.simulate(hour: 6) }
                Button("Midday") { manager.simulate(hour: 12) }
                Button("Sunset") { manager.simulate(hour: 20) }
                Button("Night") { manager.simulate(hour: 23, month: 12, day: 21) }
            }.disabled(manager.busy)
            Text("Presets use fixed local times, not calculated sunrise or sunset.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DatePicker("Custom local time", selection: $manager.customDate,
                       displayedComponents: [.date, .hourAndMinute])
                .disabled(manager.busy)
            HStack {
                Button("Apply custom time") { manager.applyCustomDate() }
                Button("Return to Live Solar") { manager.returnToLive() }
            }.disabled(manager.busy)
            }
            if manager.tab == 2 {
                Divider()
                Toggle("Launch manager at login", isOn: Binding(
                    get: { manager.launchAtLogin }, set: { manager.setLaunchAtLogin($0) }
                ))
                Toggle("Start overlay with manager", isOn: Binding(
                    get: { manager.autoStartOverlay }, set: { manager.setAutoStart($0) }
                ))
                Toggle("Recover unexpected overlay exits", isOn: Binding(
                    get: { manager.autoRecover }, set: { manager.setAutoRecover($0) }
                ))
                Text("Recovery only runs while the manager is open. Stop prevents automatic relaunch; repeated failures pause recovery.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("Diagnostics").font(.headline)
                Text(manager.diagnostics).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                if manager.validationIssues.isEmpty {
                    Label("Validation passed", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    Text("Validation findings").font(.headline)
                    ForEach(manager.validationIssues, id: \.self) { issue in
                        Text("• " + issue).font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    Button("Validate") { manager.validateInstallation() }
                    Button("Export diagnostics…") { manager.exportDiagnostics() }
                }
                HStack {
                    Button("Run Setup Assistant Again") { manager.beginSetup() }
                    Button("Clear simulated time") { manager.repairSimulatedTime() }
                        .disabled(!manager.testMode)
                }
                Text("Recent manager events").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(manager.recentEvents, id: \.self) { entry in
                            Text(entry).font(.system(.caption2, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.frame(height: 95)
                Text("Events are session-only; no location coordinates are logged.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("Build") { manager.build() }
                Button("Restart") { manager.restart() }
                Button("Stop") { manager.stop() }
            }.disabled(manager.busy)
            Button("Build & Restart") { manager.build(andRestart: true) }
                .disabled(manager.busy)
            Button("Refresh status") { manager.reload(); manager.validateInstallation() }
            if !manager.detail.isEmpty {
                ScrollView { Text(manager.detail).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 110)
            }
            Divider()
            Button("Quit Manager") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 490, height: 590)
        .onAppear { manager.startClock() }
        .onDisappear { manager.stopClock() }
    }

    private var setupWizard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Dynamic Desktop Setup").font(.headline)
                Spacer()
                Text("\(manager.setupStep + 1) of 4").foregroundStyle(.secondary)
            }
            ProgressView(value: Double(manager.setupStep + 1), total: 4)
            Divider()
            if manager.setupStep == 0 {
                Text("Welcome to Dynamic Desktop").font(.title3).bold()
                Text("Configure your wallpaper locally. Nothing is uploaded, and existing configuration values are preserved until you finish.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("The manager currently runs alongside your source repository. This wizard does not install or bundle Apple wallpaper images.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if manager.setupStep == 1 {
                Text("Choose a wallpaper collection").font(.title3).bold()
                Picker("Collection", selection: $manager.setupSet) {
                    ForEach(manager.sets, id: \.self) { Text($0).tag($0) }
                }
                Button("Import collection folder…") { manager.importWallpaperCollection() }
                Text("Import a folder containing 'Folder Name - 01.jpg' through 08.jpg (16 for Solar Gradients). The source is copied, never overwritten.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = manager.currentPreviewURL, manager.setupSet == manager.selectedSet,
                   let preview = NSImage(contentsOf: url) {
                    Image(nsImage: preview).resizable().scaledToFit().frame(height: 115)
                }
                Text("Found \(manager.sets.count) collection(s)").font(.caption)
            } else if manager.setupStep == 2 {
                Text("Solar and transition settings").font(.title3).bold()
                Toggle("Use solar-based wallpaper changes", isOn: $manager.setupSolar)
                if manager.setupSolar {
                    TextField("Latitude (decimal degrees)", text: $manager.setupLatitude)
                    TextField("Longitude (decimal degrees)", text: $manager.setupLongitude)
                    Text("Coordinates are stored only in your local wallpaper-config.json. No Location Services or network access required.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Static mode uses a separate wallpaper.jpg (or other supported image) in the repository, not the selected collection.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Crossfade")
                    Slider(value: $manager.setupFade, in: 0...10, step: 0.5)
                    Text(String(format: "%.1f s", manager.setupFade)).monospacedDigit()
                }
            } else {
                Text("Ready to finish").font(.title3).bold()
                Text("Collection: \(manager.setupSet)")
                Text("Mode: \(manager.setupSolar ? "Solar" : "Static")")
                Text(String(format: "Crossfade: %.1f seconds", manager.setupFade))
                Toggle("Start or restart overlay after setup", isOn: $manager.setupStart)
                Text("Finish writes wallpaper-config.json atomically. Your previous file is untouched until then.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !manager.setupInfo.isEmpty { Text(manager.setupInfo).font(.caption).foregroundStyle(.secondary) }
            if !manager.setupError.isEmpty {
                Text(manager.setupError).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button("Cancel") { manager.cancelSetup() }
                Spacer()
                Button("Back") { manager.setupStep -= 1; manager.setupError = "" }
                    .disabled(manager.setupStep == 0)
                if manager.setupStep < 3 {
                    Button("Continue") {
                        manager.setupError = ""
                        if manager.setupStep == 1 && !manager.sets.contains(manager.setupSet) {
                            manager.setupError = "Choose or import a collection before continuing."
                        } else {
                            manager.setupStep += 1
                        }
                    }
                } else {
                    Button("Finish") { manager.finishSetup() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

@main
struct DynamicDesktopManagerApp: App {
    var body: some Scene {
        MenuBarExtra("Dynamic Desktop", systemImage: "sun.horizon") {
            ManagerView()
        }.menuBarExtraStyle(.window)
    }
}
