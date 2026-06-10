import AppKit
import SwiftUI

struct ToolShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt
    var displayName: String

    func matches(_ event: NSEvent) -> Bool {
        keyCode == event.keyCode && modifiers == Self.normalizedModifiers(event.modifierFlags)
    }

    static func normalizedModifiers(_ flags: NSEvent.ModifierFlags) -> UInt {
        flags.intersection([.command, .shift, .option, .control]).rawValue
    }

    static func from(event: NSEvent) -> ToolShortcut? {
        guard let key = event.charactersIgnoringModifiers?.uppercased(), !key.isEmpty else { return nil }
        var parts: [String] = []
        let flags = event.modifierFlags
        if flags.contains(.control) { parts.append("Control") }
        if flags.contains(.option) { parts.append("Option") }
        if flags.contains(.shift) { parts.append("Shift") }
        if flags.contains(.command) { parts.append("Command") }
        parts.append(key)
        return ToolShortcut(
            keyCode: event.keyCode,
            modifiers: normalizedModifiers(flags),
            displayName: parts.joined(separator: " + ")
        )
    }

}

@MainActor
final class ToolKeybindStore: ObservableObject {
    @Published private(set) var shortcuts: [ToolSection: ToolShortcut] = [:]
    @Published var recordingSection: ToolSection?

    var onTrigger: ((ToolSection) -> Void)?

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var lastTriggerTimes: [ToolSection: CFAbsoluteTime] = [:]
    private let defaults = UserDefaults.standard
    private let key = "macSpeedrunningTools.toolShortcuts.v1"
    private let triggerCooldown: CFTimeInterval = 0.06

    init() {
        load()
        installMonitors()
    }

    func shortcut(for section: ToolSection) -> ToolShortcut? {
        shortcuts[section]
    }

    func beginRecording(_ section: ToolSection) {
        recordingSection = section
    }

    func clear(_ section: ToolSection) {
        shortcuts[section] = nil
        save()
    }

    private func installMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let shouldPassEvent = MainActor.assumeIsolated {
                self.handle(event)
            }
            return shouldPassEvent ? event : nil
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                _ = self?.handle(event)
            }
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        if let recordingSection {
            guard !event.isARepeat else { return false }
            if let shortcut = ToolShortcut.from(event: event) {
                shortcuts[recordingSection] = shortcut
                self.recordingSection = nil
                save()
            }
            return false
        }

        guard let section = shortcuts.first(where: { $0.value.matches(event) })?.key else {
            return true
        }
        guard !event.isARepeat else { return false }
        trigger(section)
        return true
    }

    private func trigger(_ section: ToolSection) {
        guard recordingSection == nil else { return }
        let now = CFAbsoluteTimeGetCurrent()
        if let last = lastTriggerTimes[section], now - last < triggerCooldown {
            return
        }
        lastTriggerTimes[section] = now
        onTrigger?(section)
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: ToolShortcut].self, from: data)
        else { return }
        shortcuts = decoded.reduce(into: [:]) { result, pair in
            if let section = ToolSection(rawValue: pair.key) {
                result[section] = pair.value
            }
        }
    }

    private func save() {
        let encoded = shortcuts.reduce(into: [String: ToolShortcut]()) { result, pair in
            result[pair.key.rawValue] = pair.value
        }
        if let data = try? JSONEncoder().encode(encoded) {
            defaults.set(data, forKey: key)
            defaults.synchronize()
        }
    }
}

struct ToolKeybindSection: View {
    @EnvironmentObject private var hub: ToolHub
    let section: ToolSection

    var body: some View {
        SectionBox(title: "Keybind") {
            HStack(spacing: 10) {
                Text(hub.keybinds.shortcut(for: section)?.displayName ?? "Not set")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(hub.keybinds.recordingSection == section ? "Press keys..." : "Set") {
                    hub.keybinds.beginRecording(section)
                }
                .buttonStyle(.bordered)

                Button("Clear") {
                    hub.keybinds.clear(section)
                }
                .buttonStyle(.bordered)
                .disabled(hub.keybinds.shortcut(for: section) == nil)
            }
        }
    }
}
