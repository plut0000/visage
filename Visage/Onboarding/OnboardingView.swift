import SwiftUI

struct OnboardingWindowView: View {
    @Bindable var controller: OnboardingController

    var body: some View {
        VStack(spacing: 0) {
            progress
            Divider().opacity(0.2)
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)
        }
        .frame(width: 720, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var progress: some View {
        HStack(spacing: 8) {
            Text("Visage")
                .font(.headline)
            Spacer()
            ProgressView(value: controller.progress)
                .frame(width: 180)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch controller.step {
        case .welcome:
            intro(
                title: "Unlock this Mac with a glance",
                body: "Visage watches the webcam when the screen locks. If it’s you — and you look alive — it types your password. Everything stays on this Mac."
            ) {
                Button("Continue") { controller.advance() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        case .warning:
            intro(
                title: "This is convenience, not Face ID hardware",
                body: "A Mac webcam is 2D. Visage can reject a printed photo and many phone screens, especially with Heavy liveness. It will not reliably defeat a video of you. macOS has no API for a real biometric login, so Visage types the password you store."
            ) {
                Button("I understand") { controller.advance() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        case .permissions:
            VStack(alignment: .leading, spacing: 18) {
                titleBlock("Two permissions", "Camera to see you. Accessibility to type on the lock screen.")
                permissionRow("Camera", granted: controller.camera.permission == .granted)
                permissionRow("Accessibility", granted: controller.session.accessibilityGranted)
                if let error = controller.camera.errorMessage {
                    Text(error).foregroundStyle(.red).font(.callout)
                }
                Spacer()
                HStack {
                    Button("Back") { controller.back() }
                    Spacer()
                    Button("Grant permissions") { controller.requestPermissions() }
                    Button("Continue") { controller.advance() }
                        .buttonStyle(.borderedProminent)
                        .disabled(controller.camera.permission != .granted || !controller.session.accessibilityGranted)
                }
            }
            .onAppear { controller.session.refreshAccessibilityStatus() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                controller.session.refreshAccessibilityStatus()
            }
        case .session:
            VStack(alignment: .leading, spacing: 18) {
                titleBlock("Protect the vault", "Touch ID (or your device password) unlocks the key that encrypts your face embeddings and login password.")
                if let error = controller.errorMessage ?? controller.session.sessionError {
                    Text(error).foregroundStyle(.red)
                }
                Spacer()
                HStack {
                    Button("Back") { controller.back() }
                    Spacer()
                    Button("Authenticate") {
                        Task { await controller.unlockSession() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        case .name:
            VStack(alignment: .leading, spacing: 18) {
                titleBlock("Name this face", "You can enroll more people later — glasses, a beard, or someone who shares the Mac.")
                TextField("Name", text: $controller.identityName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Spacer()
                HStack {
                    Button("Back") { controller.back() }
                    Spacer()
                    Button("Start capture") { controller.advance() }
                        .buttonStyle(.borderedProminent)
                        .disabled(controller.identityName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        case .enroll:
            enrollment
        case .password:
            VStack(alignment: .leading, spacing: 16) {
                titleBlock("Store your Mac password", "Used only to type into the lock screen after a match. Encrypted with AES-GCM behind Touch ID.")
                SecureField("Mac login password", text: $controller.password)
                    .textFieldStyle(.roundedBorder)
                SecureField("Confirm password", text: $controller.confirmPassword)
                    .textFieldStyle(.roundedBorder)
                if let error = controller.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
                Spacer()
                HStack {
                    Button("Back") { controller.back() }
                    Spacer()
                    Button("Save and finish") {
                        Task { await controller.savePasswordAndFinish() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        case .done:
            intro(
                title: "You’re set",
                body: "Lock the Mac, look at the camera, and Visage will try to let you in. Turn it off any time from the menu bar."
            ) {
                Button("Open Settings") { controller.finish() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }

    private var enrollment: some View {
        HStack(alignment: .top, spacing: 24) {
            ZStack {
                CameraPreviewView(session: controller.camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                Circle()
                    .strokeBorder(.white.opacity(0.85), lineWidth: 3)
                    .frame(width: 210, height: 210)
                VStack {
                    Spacer()
                    Text(controller.liveHint)
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(.bottom, 16)
                }
            }
            .frame(width: 360, height: 400)

            VStack(alignment: .leading, spacing: 12) {
                titleBlock("Capture nine angles", controller.currentPose.instruction)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(EnrollmentPose.allCases) { pose in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(controller.capturedPoses.contains(pose) ? Color.green.opacity(0.85) : Color.secondary.opacity(0.2))
                            .frame(height: 36)
                            .overlay {
                                Text(pose.storageName.replacingOccurrences(of: "_", with: " "))
                                    .font(.caption2)
                                    .foregroundStyle(controller.capturedPoses.contains(pose) ? .white : .primary)
                            }
                            .overlay {
                                if controller.currentPose == pose {
                                    RoundedRectangle(cornerRadius: 8).stroke(.white, lineWidth: 2)
                                }
                            }
                    }
                }
                Text("\(controller.capturedPoses.count) of \(EnrollmentPose.allCases.count) poses")
                    .foregroundStyle(.secondary)
                if let error = controller.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
                Spacer()
                Button("Back") { controller.back() }
            }
        }
        .onAppear { controller.startEnrollmentLoop() }
    }

    private func intro(title: String, body: String, @ViewBuilder action: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            FaceIDRingsView(state: .scanning)
                .frame(height: 90)
            titleBlock(title, body)
            Spacer()
            HStack {
                Spacer()
                action()
            }
        }
    }

    private func titleBlock(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.weight(.semibold))
            Text(body).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionRow(_ title: String, granted: Bool) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
            Text(title)
            Spacer()
            Text(granted ? "Ready" : "Needed")
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
