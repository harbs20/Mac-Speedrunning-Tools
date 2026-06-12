import AppKit
import Combine
import SwiftUI

private struct WindowBackdropPersistedSettings: Codable {
    var backgroundColorHex: String
    var emptyZoneColorHex: String
    var imageURLString: String?
    var imageFitMode: ImageFitMode
    var opacity: Double
    var blurRadius: Double
    var coverMenuBar: Bool
    var affectMode: WindowAffectMode?
    var specifiedWindowTargets: [WindowTargetIdentity]?
}

@MainActor
final class WindowBackdropState: ObservableObject {
    private static let settingsKey = "macSpeedrunningTools.windowBackdrop.settings.v1"

    @Published var windows: [TrackedWindow] = []
    @Published var activeWindow: TrackedWindow?
    @Published var backgroundColor = Color(red: 0.08, green: 0.11, blue: 0.13) { didSet { persistSettings() } }
    @Published var emptyZoneColor = Color.black { didSet { persistSettings() } }
    @Published var imageURL: URL? { didSet { persistSettings() } }
    @Published var imageFitMode = ImageFitMode.keepAspectRatio { didSet { persistSettings() } }
    @Published var opacity = 1.0 { didSet { persistSettings() } }
    @Published var blurRadius = 0.0 { didSet { persistSettings() } }
    @Published var coverMenuBar = false { didSet { persistSettings() } }
    @Published var affectMode = WindowAffectMode.allWindows {
        didSet {
            persistSettings()
            syncToFrontmostWindow()
        }
    }
    @Published var specifiedWindowTargets: [WindowTargetIdentity] = [] {
        didSet {
            persistSettings()
            syncToFrontmostWindow()
        }
    }
    @Published var status = "Press Start, then click any window. The rest of that display becomes the backdrop."
    @Published private(set) var isBackdropVisible = false
    @Published var isBackdropEnabled = false {
        didSet { isBackdropEnabled ? startBackdrop() : stopBackdrop() }
    }

    private let tracker = WindowTracker()
    private let backdropController = BackdropWindowController()
    private var cancellables: Set<AnyCancellable> = []
    private var syncTimer: Timer?
    private var isLoadingSettings = false

    init() {
        loadSettings()

        tracker.$windows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] windows in
                guard let self else { return }
                self.windows = windows
            }
            .store(in: &cancellables)

        tracker.start()
    }

    func refreshWindows() {
        tracker.refresh()
    }

    func isSpecifiedTarget(_ window: TrackedWindow) -> Bool {
        isSpecifiedTarget(window.targetIdentity)
    }

    func isSpecifiedTarget(_ identity: WindowTargetIdentity) -> Bool {
        specifiedWindowTargets.contains(identity)
    }

    func setSpecifiedTarget(_ window: TrackedWindow, enabled: Bool) {
        setSpecifiedTarget(window.targetIdentity, enabled: enabled)
    }

    func setSpecifiedTarget(_ identity: WindowTargetIdentity, enabled: Bool) {
        if enabled {
            guard !specifiedWindowTargets.contains(identity) else { return }
            specifiedWindowTargets.append(identity)
        } else {
            specifiedWindowTargets.removeAll { $0 == identity }
        }
    }

    func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .heic, .webP]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK {
            imageURL = panel.url
        }
    }

    func clearImage() {
        imageURL = nil
    }

    func startOrStopBackdrop() {
        isBackdropEnabled.toggle()
    }

    func toggleBackdropVisibility() {
        guard isBackdropEnabled else { return }
        if isBackdropVisible {
            hideBackdrop()
        } else {
            showBackdrop()
        }
    }

    private func startBackdrop() {
        isBackdropVisible = true
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncToFrontmostWindow()
            }
        }

        syncToFrontmostWindow()
        status = activeWindow == nil
            ? "Backdrop started. Click a normal app window to attach it."
            : "Backdrop following \(activeWindow?.displayName ?? "frontmost window")."
    }

    private func stopBackdrop() {
        syncTimer?.invalidate()
        syncTimer = nil
        hideBackdrop()
        status = "Backdrop stopped."
    }

    private func showBackdrop() {
        isBackdropVisible = true
        syncToFrontmostWindow()
    }

    private func hideBackdrop() {
        isBackdropVisible = false
        backdropController.close()
        if isBackdropEnabled {
            status = "Backdrop hidden. The tracker is still running."
        }
    }

    private func syncToFrontmostWindow() {
        guard isBackdropVisible else {
            status = "Backdrop hidden. The tracker is still running."
            return
        }

        guard let window = targetWindowForCurrentMode() else {
            activeWindow = nil
            backdropController.close()
            if affectMode == .specifiedWindowsOnly {
                status = specifiedWindowTargets.isEmpty
                    ? "Choose at least one detected window to affect."
                    : "Waiting for a specified window to be focused."
            } else {
                status = "No target window found. Click a normal window."
            }
            return
        }

        let previousWindowID = activeWindow?.id
        activeWindow = window
        syncBackdrop(to: window)

        if previousWindowID != window.id {
            status = "Backdrop following \(window.displayName)."
        }
    }

    private func targetWindowForCurrentMode() -> TrackedWindow? {
        switch affectMode {
        case .allWindows:
            return tracker.frontmostWindow()
        case .specifiedWindowsOnly:
            return tracker.frontmostWindow(matching: specifiedWindowTargets)
        }
    }

    private func syncBackdrop(to window: TrackedWindow) {
        let configuration = BackdropConfiguration(
            color: NSColor(backgroundColor),
            emptyZoneColor: NSColor(emptyZoneColor),
            imageURL: imageURL,
            imageFitMode: imageFitMode,
            opacity: opacity,
            blurRadius: blurRadius,
            coverMenuBar: coverMenuBar
        )
        backdropController.show(behind: window, configuration: configuration)
    }

    private func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: Self.settingsKey),
              let settings = try? JSONDecoder().decode(WindowBackdropPersistedSettings.self, from: data)
        else { return }

        isLoadingSettings = true
        defer { isLoadingSettings = false }

        if let color = NSColor.fromHex(settings.backgroundColorHex) {
            backgroundColor = Color(nsColor: color)
        }
        if let color = NSColor.fromHex(settings.emptyZoneColorHex) {
            emptyZoneColor = Color(nsColor: color)
        }
        if let imageURLString = settings.imageURLString {
            imageURL = URL(fileURLWithPath: imageURLString)
        } else {
            imageURL = nil
        }
        imageFitMode = settings.imageFitMode
        opacity = settings.opacity
        blurRadius = settings.blurRadius
        coverMenuBar = settings.coverMenuBar
        affectMode = settings.affectMode ?? .allWindows
        specifiedWindowTargets = settings.specifiedWindowTargets ?? []
    }

    private func persistSettings() {
        guard !isLoadingSettings else { return }

        let settings = WindowBackdropPersistedSettings(
            backgroundColorHex: NSColor(backgroundColor).hexString,
            emptyZoneColorHex: NSColor(emptyZoneColor).hexString,
            imageURLString: imageURL?.path,
            imageFitMode: imageFitMode,
            opacity: opacity,
            blurRadius: blurRadius,
            coverMenuBar: coverMenuBar,
            affectMode: affectMode,
            specifiedWindowTargets: specifiedWindowTargets
        )

        guard let data = try? JSONEncoder().encode(settings) else { return }
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: Self.settingsKey)
        defaults.synchronize()
    }
}
