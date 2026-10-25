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
    private var clockTimer: Timer?
    @Published var launchAtLogin = false
    @Published var autoStartOverlay = false
    @Published var autoRecover = false
    @Published var diagnostics = ""
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
        if autoStartOverlay && !previouslyRunning { launchOverlay(reason: "Automatic startup") }
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
        let exists = FileManager.default.fileExists(atPath: config.path)
        let json = (try? Data(contentsOf: config)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let configState = !exists ? "Missing" : (json == nil ? "Invalid JSON" : "Valid JSON")
        let set = (json?["wallpaperSet"] as? String) ?? "Unknown"
        let mode = (json?["mode"] as? String) ?? "Unknown"
        let frameCount = ((try? FileManager.default.contentsOfDirectory(atPath: images.appendingPathComponent(set).path)) ?? []).filter { $0.hasSuffix(".jpg") }.count
        diagnostics = "Overlay: \(running ? "Running" : "Stopped") | Config: \(configState)\nMode: \(mode) | Set: \(set) | Images: \(frameCount)\nSimulation: \(json?["testDateTime"] == nil ? "Off" : "On") | Recovery: \(autoRecover ? "On" : "Off")"
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Dynamic Desktop Manager").font(.headline)
                Spacer()
                Text(manager.status).foregroundStyle(.secondary)
            }
            Picker("Section", selection: $manager.tab) {
                Text("Wallpaper").tag(0)
                Text("Testing").tag(1)
                Text("System").tag(2)
            }.pickerStyle(.segmented)
            if manager.tab == 0 {
            Picker("Wallpaper set", selection: Binding(
                get: { manager.selectedSet },
                set: { manager.choose($0) }
            )) {
                ForEach(manager.sets, id: \.self) { Text($0).tag($0) }
            }
            .disabled(manager.sets.isEmpty || manager.busy)
            if let url = manager.currentPreviewURL, let preview = NSImage(contentsOf: url) {
                HStack(spacing: 12) {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 150, height: 86)
                        .clipped()
                        .cornerRadius(8)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(manager.selectedSet).font(.subheadline).bold()
                        Text("Collection preview").font(.caption).foregroundStyle(.secondary)
                        Text("Representative image, not the current solar frame")
                            .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
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
            Button("Refresh status") { manager.reload() }
            if !manager.detail.isEmpty {
                ScrollView { Text(manager.detail).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 110)
            }
            Divider()
            Button("Quit Manager") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 490)
        .onAppear { manager.startClock() }
        .onDisappear { manager.stopClock() }
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
