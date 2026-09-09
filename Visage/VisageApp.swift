import SwiftUI
import AppKit

@main
struct VisageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let environment = AppEnvironment()
    private var statusItem: NSStatusItem?
    private var sessionMenuItem: NSMenuItem?
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        if !AppSettings.shared.hasCompletedOnboarding {
            presentOnboardingIfNeeded()
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(named: "MenuBarIcon")
        icon?.isTemplate = true
        if let iconSize = icon?.size, iconSize.height > 0 {
            let height: CGFloat = 16
            icon?.size = NSSize(width: height * iconSize.width / iconSize.height, height: height)
        }
        item.button?.image = icon ?? NSImage(systemSymbolName: "faceid", accessibilityDescription: "Visage")

        let menu = NSMenu()
        menu.delegate = self
        let sessionItem = NSMenuItem(title: "", action: #selector(toggleSession), keyEquivalent: "")
        sessionItem.target = self
        menu.addItem(sessionItem)
        sessionMenuItem = sessionItem

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Visage", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        updateSessionMenuItem()
    }

    func presentOnboardingIfNeeded() {
        guard !AppSettings.shared.hasCompletedOnboarding else { return }
        if environment.onboarding == nil {
            let controller = OnboardingController(
                session: environment.session,
                pipeline: environment.unlock.pipeline
            )
            controller.onComplete = { [weak self] in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
                self?.environment.onboarding = nil
                self?.revealSettingsWindow()
            }
            environment.onboarding = controller
        }
        guard let controller = environment.onboarding else { return }
        if onboardingWindow == nil {
            let hosting = NSHostingController(rootView: OnboardingWindowView(controller: controller))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Set up Visage"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 720, height: 540))
            window.center()
            window.isReleasedWhenClosed = false
            onboardingWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { flag }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateSessionMenuItem()
        environment.session.refreshAccessibilityStatus()
        environment.session.refreshCredentialStatus()
    }

    private func updateSessionMenuItem() {
        guard let sessionMenuItem else { return }
        let unlocked = environment.session.isSessionUnlocked
        sessionMenuItem.title = unlocked ? "Lock Vault" : "Unlock Vault…"
        sessionMenuItem.image = NSImage(
            systemSymbolName: unlocked ? "lock.open.fill" : "lock.fill",
            accessibilityDescription: nil
        )
    }

    @objc private func toggleSession() {
        if environment.session.isSessionUnlocked {
            environment.session.lockSession()
        } else {
            Task { await environment.session.unlockSession() }
        }
    }

    @objc private func openSettingsWindow() {
        revealSettingsWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func revealSettingsWindow() {
        guard AppSettings.shared.hasCompletedOnboarding else {
            presentOnboardingIfNeeded()
            return
        }
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsRootView(environment: environment))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Visage Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 840, height: 560))
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing.canBecomeMain else { return }
        if closing === onboardingWindow { onboardingWindow = nil }
        if closing === settingsWindow { settingsWindow = nil }
        let stillOpen = NSApp.windows.contains { $0 !== closing && $0.canBecomeMain && $0.isVisible }
        guard !stillOpen else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
