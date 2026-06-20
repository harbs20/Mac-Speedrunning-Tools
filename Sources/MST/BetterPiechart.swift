import AppKit
import CoreGraphics
import SwiftUI

struct PersistedRect: Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

@MainActor
final class ProjectorModel: ObservableObject {
    @Published var correctedImage: CGImage?
    @Published var entityCounterImage: CGImage?
}

struct CorrectedPiePreviewCard: View {
    var image: CGImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black)

            if let image {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .clipShape(Circle())
                    .padding(18)
            } else {
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 2)
                    .padding(18)
            }
        }
    }
}

struct ProjectedPieView: View {
    var image: CGImage?
    var entityCounterImage: CGImage?

    var body: some View {
        GeometryReader { proxy in
            let hasCounter = entityCounterImage != nil
            let counterSpacing = hasCounter ? max(10, proxy.size.height * 0.04) : 0
            let counterHeight = hasCounter ? min(34, proxy.size.height * 0.12) : 0
            let pieSide = min(
                proxy.size.width * 0.84,
                (proxy.size.height - counterHeight - counterSpacing) * 0.92
            )

            VStack(spacing: counterSpacing) {
                ZStack {
                    if let image {
                        Image(decorative: image, scale: 1.0)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: pieSide, height: pieSide)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .stroke(Color.white.opacity(0.72), lineWidth: 2)
                            .frame(width: pieSide, height: pieSide)
                    }
                }

                if let entityCounterImage {
                    Image(decorative: entityCounterImage, scale: 1.0)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(maxWidth: pieSide * 0.9, maxHeight: counterHeight)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

struct ProjectorHostView: View {
    @ObservedObject var model: ProjectorModel

    var body: some View {
        ProjectedPieView(image: model.correctedImage, entityCounterImage: model.entityCounterImage)
            .background(Color.clear)
            .ignoresSafeArea()
    }
}

final class ProjectorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class ProjectorWindowController: NSObject, NSWindowDelegate {
    private var window: ProjectorPanel?
    private weak var model: ProjectorModel?
    private var alwaysOnTop = true
    private var showTitlebar = false
    var onFrameChange: ((CGRect) -> Void)?

    var frame: CGRect? { window?.frame }

    func show(model: ProjectorModel, alwaysOnTop: Bool, showTitlebar: Bool, initialFrame: CGRect? = nil) {
        self.model = model
        self.alwaysOnTop = alwaysOnTop
        self.showTitlebar = showTitlebar

        rebuildWindowIfNeeded(initialFrame: initialFrame)
        applyWindowLevel()

        if window?.isVisible != true && initialFrame == nil {
            window?.center()
        }
        window?.orderFrontRegardless()
        if let frame = window?.frame {
            onFrameChange?(frame)
        }
    }

    func setAlwaysOnTop(_ value: Bool) {
        alwaysOnTop = value
        applyWindowLevel()
    }

    func setShowTitlebar(_ value: Bool) {
        guard showTitlebar != value else { return }
        showTitlebar = value
        rebuildWindowIfNeeded()
    }

    func setVisible(_ isVisible: Bool) {
        guard let window else { return }
        if isVisible {
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    func windowDidMove(_ notification: Notification) {
        if let frame = window?.frame {
            onFrameChange?(frame)
        }
    }

    func windowDidResize(_ notification: Notification) {
        if let frame = window?.frame {
            onFrameChange?(frame)
        }
    }

    private func applyWindowLevel() {
        guard let window else { return }
        window.level = alwaysOnTop ? .statusBar : .normal
    }

    private func rebuildWindowIfNeeded(initialFrame: CGRect? = nil) {
        guard let model else { return }
        let preserveFrame = window?.frame
        let wasVisible = window?.isVisible ?? false

        window?.delegate = nil
        window?.orderOut(nil)

        let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let defaultFrame = preserveFrame ?? initialFrame ?? CGRect(
            x: screenFrame.midX - 190,
            y: screenFrame.midY - 170,
            width: 380,
            height: 340
        )

        let styleMask: NSWindow.StyleMask = showTitlebar
            ? [.titled, .closable, .miniaturizable, .resizable]
            : [.borderless]

        let window = ProjectorPanel(
            contentRect: defaultFrame,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ProjectorHostView(model: model))

        if showTitlebar {
            window.title = "Better Piechart Projector"
            window.hasShadow = true
            window.ignoresMouseEvents = false
            window.isMovableByWindowBackground = false
            window.titleVisibility = .visible
        } else {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isMovableByWindowBackground = false
        }

        self.window = window
        applyWindowLevel()

        if wasVisible {
            window.orderFrontRegardless()
        }
    }
}
