import AppKit
import SwiftUI

struct OverlayGeometry {
    enum Style {
        case notch
        case island
    }

    let screen: NSScreen
    let style: Style
    let notchWidth: CGFloat
    let closedSize: CGSize
    let openSize: CGSize
    let windowSize: CGSize

    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return false
            }
            return CGDisplayIsBuiltin(number) != 0
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    static func forScreen(_ screen: NSScreen) -> OverlayGeometry {
        let auxLeft = screen.auxiliaryTopLeftArea?.width ?? 0
        let auxRight = screen.auxiliaryTopRightArea?.width ?? 0
        let hasNotch = auxLeft > 0 && auxRight > 0 && (auxLeft + auxRight) < screen.frame.width * 0.9
        let notchWidth: CGFloat = hasNotch
            ? max(160, screen.frame.width - auxLeft - auxRight)
            : 180
        let style: Style = hasNotch ? .notch : .island
        let closedHeight: CGFloat = hasNotch ? 34 : 36
        let openSize = CGSize(width: max(notchWidth, 220), height: 148)
        let windowSize = CGSize(width: openSize.width + 40, height: openSize.height + 16)
        return OverlayGeometry(
            screen: screen,
            style: style,
            notchWidth: notchWidth,
            closedSize: CGSize(width: notchWidth, height: closedHeight),
            openSize: openSize,
            windowSize: windowSize
        )
    }
}

final class OverlayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        level = .mainMenu + 3
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }
}

enum OverlayPhase: Equatable {
    case hidden
    case closed
    case scanning
    case success
    case failure
    case onboarding
}

@Observable
@MainActor
final class OverlayController {
    static let shared = OverlayController()

    var phase: OverlayPhase = .hidden
    var isArmed: Bool { phase != .hidden }
    let failureHoldDuration: Duration = .milliseconds(1400)
    let collapseAnimationDuration: Duration = .milliseconds(450)

    private let windowController = OverlayWindowController()
    private var retryHandler: (() -> Void)?
    private var scanTimeout: Task<Void, Never>?

    private init() {
        windowController.onScreenParametersChanged = { [weak self] in
            self?.windowController.repositionIfVisible()
        }
        let root = OverlayRootView(controller: self)
        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        windowController.contentView = hosting
    }

    func arm(onRetry: @escaping () -> Void) {
        retryHandler = onRetry
        phase = .closed
        windowController.show(lockScreen: LockMonitor.isScreenActuallyLocked())
        windowController.setInteractive(true)
    }

    func beginScanning(timeout: TimeInterval) {
        phase = .scanning
        windowController.show(lockScreen: LockMonitor.isScreenActuallyLocked())
        windowController.setInteractive(false)
        scanTimeout?.cancel()
        scanTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled, let self, self.phase == .scanning else { return }
            self.phase = .closed
        }
    }

    func finish(success: Bool) {
        scanTimeout?.cancel()
        phase = success ? .success : .failure
        windowController.setInteractive(!success)
        Task { [weak self] in
            try? await Task.sleep(for: success ? .milliseconds(900) : OverlayController.shared.failureHoldDuration)
            guard let self else { return }
            if success {
                self.disarm()
            } else if self.phase == .failure {
                self.phase = .closed
                self.windowController.setInteractive(true)
            }
        }
    }

    func disarm() {
        scanTimeout?.cancel()
        phase = .hidden
        retryHandler = nil
        windowController.hide()
    }

    func presentOnboarding() {
        phase = .onboarding
        windowController.show(lockScreen: false)
        windowController.setInteractive(true, key: true)
    }

    func handleRetryTap() {
        guard phase == .closed || phase == .failure else { return }
        retryHandler?()
    }
}

@MainActor
final class OverlayWindowController {
    private var window: OverlayPanel?
    private var attachedToLockScreen = false
    var contentView: NSView? {
        didSet { window?.contentView = contentView }
    }
    var onScreenParametersChanged: (() -> Void)?

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func show(lockScreen: Bool) {
        let window = windowIfNeeded()
        reposition(window)
        window.orderFrontRegardless()
        if lockScreen, let space = LockScreenSpace.shared {
            space.attach(window)
            attachedToLockScreen = true
        }
    }

    func hide() {
        guard let window else { return }
        if attachedToLockScreen, let space = LockScreenSpace.shared {
            space.detach(window)
            attachedToLockScreen = false
        }
        window.orderOut(nil)
    }

    func setInteractive(_ interactive: Bool, key: Bool = false) {
        window?.ignoresMouseEvents = !interactive
        guard interactive, key, let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func repositionIfVisible() {
        guard let window, window.isVisible else { return }
        reposition(window)
    }

    private func windowIfNeeded() -> OverlayPanel {
        if let window { return window }
        let geometry = OverlayGeometry.preferredScreen().map(OverlayGeometry.forScreen)
            ?? OverlayGeometry.forScreen(NSScreen.main ?? NSScreen.screens[0])
        let rect = NSRect(origin: .zero, size: geometry.windowSize)
        let panel = OverlayPanel(contentRect: rect)
        panel.contentView = contentView
        window = panel
        return panel
    }

    private func reposition(_ window: OverlayPanel) {
        guard let screen = OverlayGeometry.preferredScreen() else { return }
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height
        ))
    }

    @objc private func screenParametersChanged() {
        onScreenParametersChanged?()
    }
}
