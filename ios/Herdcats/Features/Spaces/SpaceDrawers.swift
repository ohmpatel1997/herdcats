import SwiftUI

// MARK: - Space action

enum SpaceAction: Identifiable {
    case openWorktree, createWorktree, rename, close

    var id: Self { self }
}

// MARK: - Space actions drawer

/// The swipe's "More" drawer: every action for one space.
struct SpaceActionsDrawer: View {
    let space: Space
    let isWorktreeActionDisabled: Bool
    /// "Open on Left/Right" for the space, on regular width only.
    var openActions: [PaneOpenAction] = []
    let onSelect: (SpaceAction) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(space.label)
                .font(.jost(.title3, weight: .semibold))
                .lineLimit(1)

            VStack(spacing: 8) {
                ForEach(openActions) { action in
                    Button {
                        action.perform()
                        onCancel()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: action.systemImage)
                                .font(.jost(14, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 20)
                            Text(action.title)
                                .font(.jost(15, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .herdrField()
                    }
                    .buttonStyle(.herdrCard)
                    .accessibilityIdentifier("space-\(action.identifier)-button-\(space.id)")
                }
                row(.openWorktree, title: "Open Worktree", icon: "arrow.triangle.branch",
                    identifier: "space-open-worktree-button-\(space.id)")
                    .disabled(isWorktreeActionDisabled)
                row(.createWorktree, title: "Create Worktree", icon: "plus",
                    identifier: "space-create-worktree-button-\(space.id)")
                    .disabled(isWorktreeActionDisabled)
                row(.rename, title: "Rename Space", icon: "pencil",
                    identifier: "space-rename-button-\(space.id)")
                row(.close, title: "Close Space", icon: "xmark.circle",
                    identifier: "space-close-button-\(space.id)", tint: Theme.destructive)
            }

            Spacer(minLength: 0)

            Button("Cancel", action: onCancel)
                .buttonStyle(.herdrGhost())
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }

    private func row(
        _ action: SpaceAction,
        title: String,
        icon: String,
        identifier: String,
        tint: Color = Theme.accent
    ) -> some View {
        Button {
            onSelect(action)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.jost(14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 20)
                Text(title)
                    .font(.jost(15, weight: .semibold))
                    .foregroundStyle(action == .close ? tint : Theme.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .herdrField()
        }
        .buttonStyle(.herdrCard)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Create space drawer

/// Selection captured from the create-space drawer.
struct CreateSpaceRequest {
    /// The space to base the new space on; `nil` creates a blank space in
    /// herdr's default directory.
    var base: Space?
}

/// Drawer behind the Spaces screen's options menu: pick an existing space to
/// base the new space on — it opens in the same directory — or start a
/// blank one. Tapping a row creates the space and dismisses the drawer.
struct CreateSpaceDrawer: View {
    let spaces: [Space]
    let onCreate: (Space?) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Space")
                .font(.jost(.title3, weight: .semibold))
            Text("Choose a space to base the new space on — it opens in the same directory. A blank space starts in the default one.")
                .font(.jost(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    blankRow

                    if !spaces.isEmpty {
                        Text("Base on an Existing Space")
                            .font(.jost(.caption, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }

                    ForEach(spaces) { space in
                        baseRow(space)
                    }
                }
                .padding(.bottom, 4)
            }

            Button("Cancel", action: onCancel)
                .buttonStyle(.herdrGhost())
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }

    private var blankRow: some View {
        Button {
            onCreate(nil)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.square.dashed")
                    .font(.jost(13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Blank Space")
                        .font(.jost(15, weight: .semibold))
                    Text("Starts in the default directory")
                        .font(.jost(.caption))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .herdrField()
        }
        .buttonStyle(.herdrCard)
        .accessibilityLabel("Create Blank Space")
        .accessibilityIdentifier("space-create-blank-button")
    }

    private func baseRow(_ space: Space) -> some View {
        Button {
            onCreate(space)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.3x3")
                    .font(.jost(12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("#\(space.workspace.number) · \(space.label)")
                        .font(.jost(15, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(directoryHint(for: space))
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 6)
                StatusPill(status: space.status)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .herdrField()
        }
        .buttonStyle(.herdrCard)
        .accessibilityLabel("Create space based on \(space.label)")
        .accessibilityIdentifier("space-create-base-\(space.id)")
    }

    /// Directory the new space would open in: the checkout when the space
    /// has repo metadata, else the first agent's cwd, else pane/tab counts.
    private func directoryHint(for space: Space) -> String {
        if let worktree = space.workspace.worktree {
            return worktree.checkoutPath
        }
        if let cwd = space.agents.compactMap(\.cwd).first, !cwd.isEmpty {
            return cwd
        }
        let panes = space.workspace.paneCount
        let tabs = space.workspace.tabCount
        return "\(panes) pane\(panes == 1 ? "" : "s") · \(tabs) tab\(tabs == 1 ? "" : "s")"
    }
}

// MARK: - Open worktree drawer

/// Selection captured from the open-worktree drawer.
struct OpenWorktreeRequest {
    var space: Space
    var path: String?
    var branch: String?
}

struct OpenWorktreeDrawer: View {
    let space: Space
    let connection: HerdrConnection
    let onOpen: (_ path: String?, _ branch: String?) -> Void
    let onCancel: () -> Void

    @State private var worktrees: [WorktreeEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var customBranchOrPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if isLoading && worktrees.isEmpty {
                LazyCatLoadingView(message: "Loading worktrees…")
                    .accessibilityIdentifier("worktree-content-loading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, worktrees.isEmpty {
                VStack(spacing: 14) {
                    ErrorBanner(message: errorMessage, retry: {
                        Task { await loadWorktrees() }
                    })
                    customInputSection
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !worktrees.isEmpty {
                            Text("Existing worktrees")
                                .font(.jost(.caption, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)

                            ForEach(worktrees) { entry in
                                worktreeRow(entry)
                            }
                        } else {
                            ContentUnavailableView(
                                "No worktrees found",
                                systemImage: "arrow.triangle.branch",
                                description: Text("No additional Git worktrees were found for this repository.")
                            )
                            .padding(.vertical, 8)
                        }

                        customInputSection
                    }
                    .padding(.bottom, 4)
                }
            }

            Button("Cancel", action: onCancel)
                .buttonStyle(.herdrGhost())
                .accessibilityIdentifier("open-worktree-cancel-button")
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .task {
            await loadWorktrees()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Open Worktree")
                .font(.jost(.title3, weight: .semibold))
            Text("Open an existing Git worktree in #\(space.workspace.number) · \(space.label) as a Herdr workspace.")
                .font(.jost(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let worktree = space.workspace.worktree {
                RepoPill(worktree: worktree)
                    .padding(.top, 2)
            }
        }
    }

    private func worktreeRow(_ entry: WorktreeEntry) -> some View {
        Button {
            onOpen(entry.path, entry.branch)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.jost(13, weight: .semibold))
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayTitle)
                        .font(.jost(15, weight: .semibold))
                        .lineLimit(1)
                    Text(entry.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 6)

                if let openId = entry.openWorkspaceId {
                    Text("Open (#\(openId))")
                        .font(.jost(.caption2, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.subtleFill, in: Capsule())
                } else if entry.isLinkedWorktree == false {
                    Text("Root")
                        .font(.jost(.caption2, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.subtleFill, in: Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .herdrField()
        }
        .buttonStyle(.herdrCard)
        .accessibilityLabel("Open worktree \(entry.displayTitle)")
        .accessibilityIdentifier("worktree-open-row-\(entry.displayTitle)")
    }

    private var customInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or open by branch or path")
                .font(.jost(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            HStack(spacing: 8) {
                TextField("Branch or path", text: $customBranchOrPath)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .herdrField()
                    .accessibilityIdentifier("open-worktree-custom-input")

                Button("Open") {
                    let trimmed = customBranchOrPath.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
                        onOpen(trimmed, nil)
                    } else {
                        onOpen(nil, trimmed)
                    }
                }
                .buttonStyle(.herdrPrimary(fullWidth: false))
                .controlSize(.small)
                .disabled(customBranchOrPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("open-worktree-custom-button")
            }
        }
    }

    private func loadWorktrees() async {
        #if DEBUG && targetEnvironment(simulator)
        if ScreenshotFixtures.enabled && ScreenshotFixtures.screen.hasPrefix("loading-audit-worktree") {
            if ScreenshotFixtures.screen.hasSuffix("retained") {
                worktrees = (try? JSONDecoder().decode([WorktreeEntry].self,
                    from: Data(#"[{"path":"/fixture/retained","branch":"retained-branch"}]"#.utf8))) ?? []
            }
            return // Hold the presentation at a pending request without networking.
        }
        #endif
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await connection.worktreeList(workspaceId: space.workspace.workspaceId)
            worktrees = result.worktrees
        } catch {
            let message = HerdrConnection.friendlyMessage(for: error)
            if !HerdrConnection.isDisconnectionOrTransitionMessage(message) {
                errorMessage = message
            }
        }
    }
}

// MARK: - Create worktree drawer

/// Selection captured from the create-worktree drawer.
struct CreateWorktreeRequest {
    var space: Space
    var name: String?
    var label: String?
}

struct CreateWorktreeDrawer: View {
    let space: Space
    let onCreate: (_ name: String?, _ label: String?) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var label = ""

    private var validationError: String? {
        WorktreeNameValidator.validate(name)
    }

    private var isValid: Bool {
        validationError == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Worktree name")
                            .font(.jost(.caption, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("e.g. my-feature (optional)", text: $name)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .herdrField()
                            .overlay {
                                if validationError != nil {
                                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                        .stroke(Theme.warning, lineWidth: 1)
                                }
                            }
                            .accessibilityIdentifier("create-worktree-name-input")
                        if let error = validationError {
                            Text(error)
                                .font(.jost(.caption2))
                                .foregroundStyle(Theme.warning)
                                .accessibilityIdentifier("create-worktree-validation-error")
                        } else {
                            Text("Herdr will generate a worktree name if left blank.")
                                .font(.jost(.caption2))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Workspace label")
                            .font(.jost(.caption, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("e.g. My Feature (optional)", text: $label)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .herdrField()
                            .accessibilityIdentifier("create-worktree-label-input")
                        Text("Display title for the new workspace. Defaults to the worktree name.")
                            .font(.jost(.caption2))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 8)
            }

            VStack(spacing: 8) {
                Button("Create Worktree") {
                    guard isValid else { return }
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
                    onCreate(
                        trimmedName.isEmpty ? nil : trimmedName,
                        trimmedLabel.isEmpty ? nil : trimmedLabel
                    )
                }
                .buttonStyle(.herdrPrimary())
                .disabled(!isValid)
                .accessibilityIdentifier("create-worktree-submit-button")

                Button("Cancel", action: onCancel)
                    .buttonStyle(.herdrGhost())
                    .accessibilityIdentifier("create-worktree-cancel-button")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New Worktree")
                .font(.jost(.title3, weight: .semibold))
            Text("Create a new Git worktree and open it in a workspace for #\(space.workspace.number) · \(space.label).")
                .font(.jost(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let worktree = space.workspace.worktree {
                RepoPill(worktree: worktree)
                    .padding(.top, 2)
            }
        }
    }
}
