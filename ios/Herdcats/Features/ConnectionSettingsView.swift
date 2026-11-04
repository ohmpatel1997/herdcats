import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ConnectionSettingsView: View {
    @Environment(AppModel.self) var appModel
    @Environment(\.dismiss) var dismiss
    let isReplay: Bool
    let original: RecentConnection
    let editing: Bool
    let switcher: ActiveMachine?
    @State var name = ""
    @State var isSwitching = false
    @State var switchConnectionError: String?
    @State private var pendingSignIn: ConnectionSignIn?
    var isConnecting: Bool { switcher == nil ? appModel.isConnecting : isSwitching }
    @State var host = ""
    @State var port = "22"
    @State var username = ""
    @State var authModeRaw = AuthMode.password.rawValue
    /// nil is Auto: connect detects TUI and Herdr Core and saves each one found.
    @State var backend: ConnectionBackend?
    @State var remember = true

    @State var credentialLoadError: String?
    @State var password = ""
    @State var keyPEM = ""
    @State var keyPassphrase = ""
    @State var rememberPassphrase = false
    @State var passwordWasEdited = false
    @State var privateKeyWasEdited = false
    @State var passphraseWasEdited = false
    @State var rememberWasEdited = false
    private let loadedPrivateKey: String?

    var passwordInput: Binding<String> {
        Binding(get: { password }, set: { password = $0; passwordWasEdited = true })
    }
    var privateKeyInput: Binding<String> {
        Binding(get: { keyPEM }, set: { keyPEM = $0; privateKeyWasEdited = true })
    }
    var passphraseInput: Binding<String> {
        Binding(get: { keyPassphrase }, set: { keyPassphrase = $0; passphraseWasEdited = true })
    }
    var rememberPassphraseInput: Binding<Bool> {
        Binding(get: { rememberPassphrase }, set: { rememberPassphrase = $0; passphraseWasEdited = true })
    }
    var rememberInput: Binding<Bool> {
        Binding(get: { remember }, set: { remember = $0; rememberWasEdited = true })
    }

    var keyIsEncrypted: Bool { (try? OpenSSHEd25519.isEncrypted(pem: keyPEM)) == true }
    @State var showPassword = false
    @State var showKey = false
    @State var keyImporterPresented = false
    @State var importErrorMessage: String?
    @State var didCopyPubKey = false
    @State var showingSetupGuide = false

    var derivedPublicKey: String? {
        try? OpenSSHEd25519.openSSHPublicKeyString(for: validatedPublicKey())
    }

    private func validatedPublicKey() throws -> Data {
        // Validate plaintext private material before enabling Connect. Encrypted
        // keys expose metadata here; unlock them only during the connection attempt.
        if try !OpenSSHEd25519.isEncrypted(pem: keyPEM) {
            _ = try OpenSSHEd25519.parseRawPrivateKey(pem: keyPEM)
        }
        return try OpenSSHEd25519.parsePublicKey(pem: keyPEM)
    }

    var maskedPrivateKey: String {
        OpenSSHEd25519.maskPrivateKey(pem: keyPEM)
    }

    var keyValidationError: String? {
        let trimmed = keyPEM.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("ssh-ed25519 ") || trimmed.hasPrefix("ssh-rsa ") || trimmed.hasPrefix("ecdsa-") {
            return "This is an SSH public key (.pub). Please import or paste your private key instead "
                + "(usually named herdcats_key or id_ed25519 without .pub)."
        }
        if trimmed.contains("BEGIN RSA PRIVATE KEY")
            || trimmed.contains("BEGIN DSA PRIVATE KEY")
            || trimmed.contains("BEGIN EC PRIVATE KEY") {
            return "This key uses an unsupported format. Herdcats requires an ed25519 OpenSSH key "
                + "(ssh-keygen -t ed25519)."
        }
        do {
            _ = try validatedPublicKey()
            return nil
        } catch let keyError as OpenSSHKeyError {
            return keyError.errorDescription
        } catch {
            return error.localizedDescription
        }
    }

    static let documentationURL = URL(string: "https://herdcats.dev/support/#connect")!

    init(connection: RecentConnection, isReplay: Bool = false, editing: Bool = false, switcher: ActiveMachine? = nil,
         defaults: UserDefaults = .standard, using keychain: KeychainOperations = KeychainStore.operations) {
        self.isReplay = isReplay
        self.original = connection
        self.editing = editing
        self.switcher = switcher
        _name = State(initialValue: connection.name ?? "")
        _host = State(initialValue: connection.host)
        _port = State(initialValue: String(connection.port))
        _username = State(initialValue: connection.username)
        _authModeRaw = State(initialValue: connection.authMode)
        // A server saved with both runtimes is edited as one, so it opens on Auto.
        let runtimes = RecentConnectionStore.savedRuntimes(of: connection, in: RecentConnectionStore.snapshot(defaults: defaults))
        _backend = State(initialValue: connection.host.isEmpty || runtimes.count > 1 ? nil : connection.backend)
        _remember = State(initialValue: connection.remember)
        var loadedPrivateKey: String?
        do {
            let loaded = try ConnectionSignIn.load(connection, using: keychain, readOnly: isReplay, includingInactiveCredentials: true)
            _password = State(initialValue: connection.authMode == "privateKey" ? loaded.otherSecret ?? "" : loaded.secret)
            loadedPrivateKey = connection.authMode == "privateKey" ? loaded.secret : loaded.otherSecret ?? ""
            _keyPEM = State(initialValue: loadedPrivateKey ?? "")
            _keyPassphrase = State(initialValue: loaded.passphrase)
            _rememberPassphrase = State(initialValue: loaded.savePassphrase)
        } catch {
            _credentialLoadError = State(initialValue: error.localizedDescription)
        }
        self.loadedPrivateKey = loadedPrivateKey
    }

    enum AuthMode: String, CaseIterable, Identifiable {
        case password
        case privateKey

        var id: String { rawValue }
        var title: String {
            switch self {
            case .password: "Password"
            case .privateKey: "Private Key"
            }
        }
    }

    var authMode: AuthMode {
        AuthMode(rawValue: authModeRaw) ?? .password
    }

    var portNumber: Int? {
        let trimmed = port.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed), (1...65_535).contains(value) else { return nil }
        return value
    }

    var canConnect: Bool {
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty,
              !username.trimmingCharacters(in: .whitespaces).isEmpty,
              portNumber != nil else { return false }
        switch authMode {
        case .password:
            return !password.isEmpty
        case .privateKey:
            return derivedPublicKey != nil && (!keyIsEncrypted || !keyPassphrase.isEmpty)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let switchConnectionError { ErrorBanner(message: switchConnectionError) }
                    if switcher == nil, let error = appModel.lastError {
                        if appModel.herdrMissingOnLastConnect {
                            MissingHerdrRecoveryCard(
                                inForm: true,
                                mismatch: appModel.runtimeMismatchOnLastConnect,
                                onConnect: connectWithInstalledRuntimeAction,
                                onSetup: { showingSetupGuide = true }
                            )
                        } else if appModel.herdrSessionUnavailableOnLastConnect {
                            SessionRecoveryCard(inForm: true)
                        } else {
                            ErrorBanner(message: error)
                        }
                    }
                    if let credentialLoadError {
                        ErrorBanner(message: credentialLoadError + " Close and reopen settings to retry loading sign-in before saving changes.")
                    }
                    connectionCard
                    footer
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.backgroundGradient)
            .safeAreaInset(edge: .bottom) {
                Button(editing ? "Save changes" : "Connect") {
                    Task { if editing { saveChanges() } else { await connect() } }
                }
                .buttonStyle(.herdrPrimary())
                .disabled((editing ? !canSaveChanges : !canConnect || credentialLoadError != nil) || isConnecting)
                .padding(16)
                .background(Theme.backgroundGradient)
            }
            .navigationTitle("Connection Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.jost(16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Close")
                    .disabled(isConnecting)
                }
            }
        }
        .overlay {
            // A sheet is presented above the root view, so it needs its own
            // loading surface while authentication and the Herdr check run.
            if isConnecting {
                LazyCatLoadingView(message: switcher?.pending?.connectionProgressMessage ?? appModel.connectionProgressMessage)
                    .background(Theme.backgroundGradient.ignoresSafeArea())
            }
        }
        .background {
            if switcher == nil {
                Color.clear.hostKeyApprovalSheet { await connect() }
            } else if let switcher, let pending = switcher.pending {
                Color.clear.hostKeyApprovalSheet(onCancelled: {
                    guard switcher.pending === pending else { return }
                    await switcher.cancelSwitch()
                    pendingSignIn = nil
                }, onApproved: {
                    guard switcher.pending === pending, let value = pendingSignIn else { return }
                    isSwitching = true
                    defer { isSwitching = false }
                    do { handleSwitchOutcome(try await switcher.finishSignIn(using: value, replay: isReplay)) }
                    catch { switchConnectionError = error.localizedDescription }
                })
                .environment(pending)
                .id(ObjectIdentifier(pending))
            }
        }
        .onAppear { switcher?.pendingHostKeyOwnedByForm = true }
        .onDisappear {
            switcher?.pendingHostKeyOwnedByForm = false
            if let switcher, let pending = switcher.pending {
                Task { if switcher.pending === pending { await switcher.cancelSwitch() } }
            }
        }
        .sheet(isPresented: $showingSetupGuide) {
            HerdrSetupGuideView(backend: backend ?? .tui)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isConnecting)
    }

    var footer: some View {
        VStack(spacing: 8) {
            if ["127.0.0.1", "localhost", "::1"].contains(host.lowercased()) {
                Text("Use a host address your iPhone can reach. This address means the iPhone itself.")
                .font(.jost(.footnote))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            Button("Connection Setup Help") { showingSetupGuide = true }
                .font(.jost(.footnote))
        }
        .padding(.horizontal, 18)
    }

    // MARK: Helpers

    var fieldShape: some Shape {
        RoundedRectangle.continuous(DesignSystem.CornerRadius.md)
    }

    func fieldLabel(_ text: String, hidden: Bool = false) -> some View {
        Group {
            if !hidden {
                Text(text)
                    .font(.jost(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    func handleKeyImport(_ result: Result<[URL], Error>) {
        importErrorMessage = nil
        switch result {
        case let .failure(error):
            if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled {
                return
            }
            importErrorMessage = "File selection failed: \(error.localizedDescription)"
        case let .success(urls):
            guard let url = urls.first else { return }
            do {
                keyPEM = try ConnectionSignIn.importPrivateKey(from: url)
                privateKeyWasEdited = true
                showKey = false
            } catch {
                importErrorMessage = error.localizedDescription
            }
        }
    }

    var destination: RecentConnection {
        RecentConnection(id: original.id, host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: portNumber ?? 0, username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            authMode: authModeRaw, remember: remember, name: name, lastConnectedAt: original.lastConnectedAt, backend: backend ?? original.backend)
    }

    var validDestination: Bool {
        !destination.host.isEmpty && !destination.username.isEmpty && portNumber != nil
    }

    var canSaveChanges: Bool {
        validDestination && credentialLoadError == nil
            && (authMode != .privateKey || keyPEM.isEmpty || keyValidationError == nil)
    }

    func signIn(defaults: UserDefaults = .standard, using keychain: KeychainOperations = KeychainStore.operations) throws -> ConnectionSignIn {
        var entry = destination
        if !editing {
            entry = RecentConnectionStore.entry(host: entry.host, port: entry.port, username: entry.username,
                authMode: entry.authMode, remember: entry.remember, name: name, backend: entry.backend, in: isReplay ? RecentConnectionStore.snapshot(defaults: defaults) : try RecentConnectionStore.load(defaults: defaults, using: keychain))
        } else if entry.backend != original.backend {
            // Picking the other runtime edits that runtime's saved entry, so this
            // one is never repointed and the server keeps one entry per runtime.
            let entries = isReplay ? RecentConnectionStore.snapshot(defaults: defaults) : try RecentConnectionStore.load(defaults: defaults, using: keychain)
            if let sibling = RecentConnectionStore.runtimes(of: original, in: entries).first(where: { $0.backend == entry.backend }) {
                entry.id = sibling.id
                entry.lastConnectedAt = sibling.lastConnectedAt
            }
        }
        let inactiveSecret = authMode == .password ? keyPEM : password
        // A new form can resolve to a saved profile it never loaded. Its empty
        // inactive field must not clear that profile's credential or passphrase.
        let inactiveWasEdited = authMode == .password ? privateKeyWasEdited : passwordWasEdited
        let editsInactiveSecret = editing || entry.id == original.id || !inactiveSecret.isEmpty || inactiveWasEdited
        return ConnectionSignIn(entry: entry, secret: authMode == .password ? password : keyPEM,
            passphrase: keyPassphrase, savePassphrase: rememberPassphrase, detectsBackend: backend == nil,
            otherSecret: editsInactiveSecret ? inactiveSecret : nil,
            credentialEdits: .init(ownerID: original.id, password: passwordWasEdited, privateKey: privateKeyWasEdited,
                passphrase: passphraseWasEdited, remember: rememberWasEdited, passphraseKey: loadedPrivateKey))
    }

    var nameWasEdited: Bool { name != (original.name ?? "") }

    func saveChanges() {
        guard canSaveChanges else { return }
        do {
            if !isReplay {
                let value = try signIn()
                if value.detectsBackend && editing {
                    try value.persistServer(from: original, updateName: nameWasEdited)
                } else {
                    try value.persist(connected: false, updateName: nameWasEdited)
                }
                try syncServerName(value)
            }
            dismiss()
        } catch { appModel.lastError = error.localizedDescription }
    }

    private func syncServerName(_ value: ConnectionSignIn) throws {
        guard nameWasEdited else { return }
        try RecentConnectionStore.renameServer(value.entry, to: value.entry.name)
    }

    func connect() async {
        guard !isConnecting, credentialLoadError == nil else { return }
        isSwitching = switcher != nil
        defer { isSwitching = false }
        do {
            let value = try signIn()
            if let switcher {
                pendingSignIn = value
                switchConnectionError = nil
                handleSwitchOutcome(try await switcher.signIn(using: value, replay: isReplay))
            } else {
                if !isReplay { try value.prepareAttempt() }
                await appModel.connect(config: value.config)
                guard case .connected = appModel.phase else { return }
                if !isReplay {
                    // Move the whole server first so detection reuses its runtimes at the new host.
                    if value.detectsBackend && editing { try value.persistServer(from: original, updateName: true) }
                    if value.detectsBackend, let backend = appModel.activeConfig?.backend {
                        try value.persistDetected(backend: backend, found: appModel.detectedBackends, updateName: true)
                    } else {
                        try value.persist(updateName: true)
                    }
                    try syncServerName(value)
                }
                dismiss()
            }
        } catch {
            if switcher != nil { switchConnectionError = error.localizedDescription }
            else { appModel.lastError = error.localizedDescription }
        }
    }

    /// The missing-runtime card's button, offered when the failed connection is
    /// this form's machine and runtime.
    var connectWithInstalledRuntimeAction: (() -> Void)? {
        guard !isReplay, let mismatch = appModel.runtimeMismatchOnLastConnect,
              appModel.lastConnectWasFor(destination) else { return nil }
        return { Task { await connectWithInstalledRuntime(mismatch.installed) } }
    }

    /// Saves the runtime the machine has as a second entry, unless one is saved
    /// already, then switches this form to it and connects. The saved entry for
    /// the missing runtime is not changed.
    func connectWithInstalledRuntime(_ installed: ConnectionBackend) async {
        guard !isConnecting, credentialLoadError == nil else { return }
        do {
            // Saving it first means the form picks that entry below. In edit mode,
            // switching the runtime alone would move this entry to the other runtime.
            _ = try signIn().siblingToConnect(installed)
        } catch {
            appModel.showPlainError(error.localizedDescription)
            return
        }
        backend = installed
        await connect()
    }

    private func handleSwitchOutcome(_ outcome: ActiveMachine.SwitchOutcome) {
        switch outcome {
        case .switched:
            do { if let pendingSignIn, !isReplay { try syncServerName(pendingSignIn) } }
            catch { appModel.lastError = error.localizedDescription }
            dismiss()
        case .alreadyActive: dismiss()
        case .failed:
            if switcher?.pending?.hostKeyChallenge == nil {
                switchConnectionError = switcher?.switchError ?? "Connection failed"
                switcher?.switchError = nil
                pendingSignIn = nil
            }
        case .needsCredentials, .superseded: pendingSignIn = nil
        }
    }
}
