import Foundation
import Observation
import AppKit

@Observable
@MainActor
final class SessionController {
    var accessibilityGranted: Bool = KeystrokeTyper.isAccessibilityTrusted()
    var hasStoredPassword: Bool = CredentialVault.hasStoredPassword()
    var isSessionUnlocked: Bool = CredentialVault.isSessionUnlocked
    var sessionError: String?
    var passwordInput: String = ""
    var statusMessage: String = "Idle"

    func refreshAccessibilityStatus() {
        accessibilityGranted = KeystrokeTyper.isAccessibilityTrusted()
    }

    func requestAccessibility() {
        KeystrokeTyper.promptForAccessibility()
        refreshAccessibilityStatus()
    }

    func refreshCredentialStatus() {
        hasStoredPassword = CredentialVault.hasStoredPassword()
        isSessionUnlocked = CredentialVault.isSessionUnlocked
    }

    func unlockSession() async {
        sessionError = nil
        do {
            try await Task.detached(priority: .userInitiated) {
                try CredentialVault.unlockSession(reason: "Authenticate to set up or use Visage")
            }.value
            isSessionUnlocked = true
        } catch {
            isSessionUnlocked = false
            sessionError = error.localizedDescription
        }
    }

    func lockSession() {
        CredentialVault.lockSession()
        isSessionUnlocked = false
    }

    func savePassword() async {
        let plaintext = passwordInput
        guard !plaintext.isEmpty else {
            statusMessage = "Enter your Mac login password first."
            return
        }
        passwordInput = ""
        do {
            try await savePassword(plaintext)
            statusMessage = "Password saved and encrypted."
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func savePassword(_ plaintext: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            guard var bytes = plaintext.data(using: .utf8) else {
                throw CredentialError.emptyPassword
            }
            defer { bytes.resetBytes(in: 0..<bytes.count) }
            try CredentialVault.savePassword(bytes)
        }.value
        hasStoredPassword = true
    }

    func deleteStoredSecrets() throws {
        try CredentialVault.deletePassword()
        EnrollmentStore.shared.deleteAll()
        hasStoredPassword = false
        isSessionUnlocked = false
        AppSettings.shared.isFaceUnlockEnabled = false
        AppSettings.shared.hasCompletedOnboarding = false
    }

    func injectStoredPassword(requireAuthoritativeLock: Bool = false) async {
        guard KeystrokeTyper.isAccessibilityTrusted() else {
            statusMessage = "Accessibility is not granted."
            return
        }
        guard CredentialVault.isSessionUnlocked else {
            statusMessage = "Session locked — authenticate with Touch ID first."
            return
        }
        if requireAuthoritativeLock {
            guard LockMonitor.isScreenActuallyLocked() else {
                statusMessage = "Skipped: the screen is not actually locked."
                return
            }
        }
        statusMessage = "Unlocking…"
        do {
            try await Task.detached(priority: .userInitiated) {
                var bytes = try CredentialVault.readPassword()
                defer { bytes.resetBytes(in: 0..<bytes.count) }
                try KeystrokeTyper.typeAndReturn(bytes)
            }.value
            statusMessage = "Password entered."
        } catch {
            statusMessage = "Unlock failed: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class SessionWatchdog {
    private let session: SessionController
    private var timer: Timer?

    init(session: SessionController) {
        self.session = session
        let timer = Timer(timeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.evaluate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.evaluate() }
        }
        evaluate()
    }

    deinit {
        timer?.invalidate()
    }

    func evaluate() {
        guard CredentialVault.isSessionUnlocked,
              let lastActivityAt = CredentialVault.lastActivityAt,
              let idleLimit = AppSettings.shared.autoLockInterval.duration
        else { return }
        guard Date().timeIntervalSince(lastActivityAt) >= idleLimit else { return }
        session.lockSession()
    }
}
