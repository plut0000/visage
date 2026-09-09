import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, faces, password, recognition, camera, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .faces: return "Your Face"
        case .password: return "Password"
        case .recognition: return "Recognition"
        case .camera: return "Camera"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .faces: return "person.crop.circle"
        case .password: return "key.fill"
        case .recognition: return "faceid"
        case .camera: return "web.camera"
        case .about: return "info.circle"
        }
    }
}

struct SettingsRootView: View {
    @Bindable var environment: AppEnvironment
    @State private var tab: SettingsTab = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $tab) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(200)
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch tab {
                case .general: GeneralSettingsPage(environment: environment)
                case .faces: FacesSettingsPage(environment: environment)
                case .password: PasswordSettingsPage(environment: environment)
                case .recognition: RecognitionSettingsPage(environment: environment)
                case .camera: CameraSettingsPage(environment: environment)
                case .about: AboutSettingsPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            environment.session.refreshAccessibilityStatus()
            environment.session.refreshCredentialStatus()
        }
    }
}

struct GeneralSettingsPage: View {
    @Bindable var environment: AppEnvironment
    @Bindable var settings = AppSettings.shared
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("Face unlock") {
                Toggle("Unlock this Mac with my face", isOn: $environment.unlock.isEnabled)
                Toggle("Show the notch animation", isOn: $settings.showUnlockAnimation)
                Toggle("Retry once if the first scan misses", isOn: $settings.autoRetryOnce)
            }
            Section("When to scan") {
                ForEach(UnlockTrigger.allCases) { trigger in
                    Toggle(isOn: Binding(
                        get: { settings.unlockTriggers.contains(trigger) },
                        set: { on in
                            if on { settings.unlockTriggers.insert(trigger) }
                            else { settings.unlockTriggers.remove(trigger) }
                        }
                    )) {
                        VStack(alignment: .leading) {
                            Text(trigger.title)
                            Text(trigger.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Session") {
                Picker("Re-lock the vault after", selection: $settings.autoLockInterval) {
                    ForEach(AutoLockInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                Toggle("Open Visage at login", isOn: Binding(
                    get: { LaunchAtLogin.isEnabled },
                    set: { newValue in
                        do {
                            try LaunchAtLogin.setEnabled(newValue)
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                        }
                    }
                ))
                if let launchError {
                    Text(launchError).foregroundStyle(.red)
                }
            }
            Section("Permissions") {
                LabeledContent("Camera") {
                    Text(environment.unlock.camera.permission == .granted ? "Allowed" : "Needed")
                }
                LabeledContent("Accessibility") {
                    HStack {
                        Text(environment.session.accessibilityGranted ? "Allowed" : "Needed")
                        if !environment.session.accessibilityGranted {
                            Button("Request") { environment.session.requestAccessibility() }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

struct FacesSettingsPage: View {
    @Bindable var environment: AppEnvironment
    @State private var enrollSheet: EnrollSheet?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !environment.session.isSessionUnlocked {
                ContentUnavailableView(
                    "Vault locked",
                    systemImage: "lock.fill",
                    description: Text("Authenticate to see enrolled faces.")
                )
                Button("Unlock") { Task { await environment.session.unlockSession() } }
                    .buttonStyle(.borderedProminent)
            } else if environment.faces.identities.isEmpty {
                ContentUnavailableView(
                    "No faces enrolled",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("Capture nine angles of your face. Images are discarded; only embeddings are stored.")
                )
                Button("Enroll a face") { startEnroll(replacing: nil) }
                    .buttonStyle(.borderedProminent)
            } else {
                List {
                    ForEach(environment.faces.identities) { identity in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(identity.name).font(.headline)
                                Text("\(identity.samples.count) samples · \(identity.isStale(comparedTo: environment.unlock.pipeline.embedder) ? "needs recapture" : identity.modelIdentifier)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("Enabled", isOn: Binding(
                                get: { identity.isEnabled },
                                set: { newValue in
                                    try? environment.faces.setEnabled(newValue, for: identity.id)
                                }
                            ))
                            .labelsHidden()
                            Button("Recapture") { startEnroll(replacing: identity) }
                            Button("Delete", role: .destructive) {
                                try? environment.faces.delete(identity)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                Button("Enroll another face") { startEnroll(replacing: nil) }
            }
            if let error {
                Text(error).foregroundStyle(.red)
            }
        }
        .navigationTitle("Your Face")
        .sheet(item: $enrollSheet) { sheet in
            OnboardingWindowView(controller: sheet.controller)
        }
    }

    private func startEnroll(replacing: FaceIdentity?) {
        let controller = OnboardingController(
            session: environment.session,
            pipeline: environment.unlock.pipeline,
            replacing: replacing
        )
        controller.onComplete = { enrollSheet = nil }
        enrollSheet = EnrollSheet(controller: controller)
    }
}

private struct EnrollSheet: Identifiable {
    let id = UUID()
    let controller: OnboardingController
}

struct PasswordSettingsPage: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        Form {
            Section("Vault") {
                LabeledContent("Session") {
                    Text(environment.session.isSessionUnlocked ? "Unlocked" : "Locked")
                }
                if environment.session.isSessionUnlocked {
                    Button("Lock session") { environment.session.lockSession() }
                } else {
                    Button("Unlock with Touch ID") {
                        Task { await environment.session.unlockSession() }
                    }
                }
                if let error = environment.session.sessionError {
                    Text(error).foregroundStyle(.red)
                }
            }
            Section("Mac password") {
                if environment.session.hasStoredPassword {
                    Text("A login password is stored, encrypted. Visage types it only after a live match at the lock screen.")
                    SecureField("New password", text: $environment.session.passwordInput)
                    Button("Save") {
                        Task { await environment.session.savePassword() }
                    }
                    .disabled(!environment.session.isSessionUnlocked || environment.session.passwordInput.isEmpty)
                    Text(environment.session.statusMessage).foregroundStyle(.secondary)
                    Button("Delete password and faces", role: .destructive) {
                        try? environment.session.deleteStoredSecrets()
                    }
                } else {
                    Text("No password stored. Face unlock cannot type into the lock screen until you save one.")
                    SecureField("Mac login password", text: $environment.session.passwordInput)
                    Button("Save password") {
                        Task { await environment.session.savePassword() }
                    }
                    .disabled(!environment.session.isSessionUnlocked)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Password")
    }
}

struct RecognitionSettingsPage: View {
    @Bindable var environment: AppEnvironment
    @Bindable var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Match") {
                LabeledContent("Similarity threshold") {
                    Text(String(format: "%.2f", environment.unlock.matchThreshold))
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { Double(environment.unlock.matchThreshold) },
                    set: { environment.unlock.matchThreshold = Float($0) }
                ), in: 0.28...0.55, step: 0.01)
                Text("ArcFace cosine similarity. Start near 0.38. Raise it if someone else can unlock; lower it if you fail in new lighting.")
                    .foregroundStyle(.secondary)
            }
            Section("Scan") {
                Stepper(value: $settings.scanSeconds, in: 4...15, step: 1) {
                    Text("Look for a face for \(Int(settings.scanSeconds)) seconds")
                }
                LabeledContent("Minimum face width") {
                    Text(String(format: "%.0f%%", settings.minimumFaceWidth * 100))
                }
                Slider(value: Binding(
                    get: { Double(settings.minimumFaceWidth) },
                    set: { settings.minimumFaceWidth = Float($0) }
                ), in: 0.10...0.35, step: 0.01)
            }
            Section("Liveness") {
                Picker("Checks", selection: $settings.livenessMode) {
                    ForEach(LivenessMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text(settings.livenessMode.detail)
                    .foregroundStyle(.secondary)
            }
            if environment.unlock.pipeline.usingFallbackEmbedder {
                Section("Model") {
                    Text("ArcFace failed to load. Using Vision Feature Print, which is much weaker. Rebuild the app so ArcFace.mlpackage is compiled into the bundle.")
                        .foregroundStyle(.orange)
                    if let reason = environment.unlock.pipeline.fallbackReason {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Recognition")
    }
}

struct CameraSettingsPage: View {
    @Bindable var settings = AppSettings.shared
    @State private var devices: [CameraDeviceInfo] = []

    var body: some View {
        Form {
            Section("Devices") {
                Picker("Default camera", selection: $settings.defaultCameraID) {
                    Text("System default").tag(Optional<String>.none)
                    ForEach(devices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                Picker("Built-in display", selection: $settings.builtInDisplayCameraID) {
                    Text("Use default").tag(Optional<String>.none)
                    ForEach(devices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                Picker("External display", selection: $settings.externalDisplayCameraID) {
                    Text("Use default").tag(Optional<String>.none)
                    ForEach(devices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Camera")
        .onAppear { devices = CameraCatalog.availableDevices() }
    }
}

struct AboutSettingsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage(size: NSSize(width: 64, height: 64)))
                    .resizable()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading) {
                    Text("Visage").font(.largeTitle.weight(.semibold))
                    Text("Face unlock for Mac").foregroundStyle(.secondary)
                }
            }
            Text("Visage is a convenience feature. It is not as secure as iPhone Face ID or Touch ID. Face embeddings and your password never leave this Mac.")
            Text("Inspired by Glance. Recognition uses InsightFace ArcFace (w600k_mbf) on Core ML. See NOTICE.md.")
                .foregroundStyle(.secondary)
            Link("InsightFace", destination: URL(string: "https://github.com/deepinsight/insightface")!)
            Spacer()
        }
        .navigationTitle("About")
    }
}
