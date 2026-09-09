import Foundation
import Observation

@Observable
@MainActor
final class AppEnvironment {
    let session: SessionController
    let faces = EnrollmentStore.shared
    let unlock: UnlockCoordinator
    let sessionWatchdog: SessionWatchdog
    var onboarding: OnboardingController?

    init() {
        let session = SessionController()
        self.session = session
        self.unlock = UnlockCoordinator(session: session)
        self.sessionWatchdog = SessionWatchdog(session: session)
    }
}
