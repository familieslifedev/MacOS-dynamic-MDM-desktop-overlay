import SwiftUI
import AppKit
import Foundation
import Darwin

@MainActor
final class Manager: ObservableObject {
    @Published var selectedSet = ""
    @Published var sets: [String] = []
    @Published var status = "Checking…"
    @Published var detail = ""
    @Published var busy = false
    @Published var testMode = false
    @Published var customDate = Date()

    // Bundle lives at <repository>/DynamicDesktopManager.app/Contents/MacOS/...
    private var repo: URL {
        Bundle.main.bundleURL.deletingLastPathComponent()
    }
    private var executable: URL { repo.appendingPathComponent("DesktopOverlayDynamic") }
    private var config: URL { repo.appendingPathComponent("wallpaper-config.json") }
    private var images: URL { repo.appendingPathComponent("Apple Dynamic Wallpapers", isDirectory: true) }

    init() { reload() }

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
        Task {
            await stopProcesses()
            busy = false
            reload()
            detail = runningPIDs().isEmpty ? "Overlay stopped." : "Overlay did not stop within 3 seconds."
        }
    }

    func restart() {
        guard !busy else { return }
        busy = true
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
            Picker("Wallpaper set", selection: Binding(
                get: { manager.selectedSet },
                set: { manager.choose($0) }
            )) {
                ForEach(manager.sets, id: \.self) { Text($0).tag($0) }
            }
            .disabled(manager.sets.isEmpty || manager.busy)
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
            Text("Presets use fixed local clock times for testing, not calculated sunrise/sunset.")
                .font(.caption2).foregroundStyle(.secondary)
            DatePicker("Custom local time", selection: $manager.customDate,
                       displayedComponents: [.date, .hourAndMinute])
                .disabled(manager.busy)
            HStack {
                Button("Apply custom time") { manager.applyCustomDate() }
                Button("Return to Live Solar") { manager.returnToLive() }
            }.disabled(manager.busy)
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
        .frame(width: 350)
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
