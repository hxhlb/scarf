import SwiftUI

/// Connections section for Settings — manages the list of known Hermes endpoints
/// (Local + saved remotes), and lets the user pick which one Scarf runs against.
///
/// Switching takes effect immediately: `AppCoordinator.activeConnection.didSet`
/// mirrors the new value into `ConnectionProvider`, and `ContentView` rebuilds
/// its subtree via `.id(activeConnection)` so every VM picks up services bound
/// to the new target.
struct ConnectionsView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var viewModel = ConnectionsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            banner
            connectionList
            addButton
        }
        .task { await viewModel.load() }
        .sheet(item: Binding(
            get: { viewModel.editing },
            set: { viewModel.editing = $0 }
        )) { _ in
            ConnectionEditSheet(viewModel: viewModel)
                .frame(minWidth: 460)
        }
        .confirmationDialog(
            "Remove this connection?",
            isPresented: Binding(
                get: { viewModel.pendingDelete != nil },
                set: { if !$0 { viewModel.pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: viewModel.pendingDelete
        ) { remote in
            Button("Remove \"\(remote.nickname)\"", role: .destructive) {
                Task { await viewModel.confirmDelete(coordinator: coordinator) }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingDelete = nil
            }
        } message: { remote in
            Text("Scarf will forget \(remote.user)@\(remote.host). SSH keys on your system are not touched.")
        }
    }

    @ViewBuilder
    private var banner: some View {
        if let text = viewModel.banner {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                Text(text)
                    .font(.caption)
                Spacer()
                Button("Dismiss") { viewModel.dismissBanner() }
                    .buttonStyle(.plain)
                    .font(.caption)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 6).fill(.blue.opacity(0.1)))
        }
    }

    private var connectionList: some View {
        VStack(spacing: 1) {
            localRow
            ForEach(viewModel.remotes) { remote in
                remoteRow(remote)
            }
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.3)))
    }

    private var localRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "laptopcomputer")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text("Local")
                    .font(.body)
                Text("~/.hermes on this Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive(.local) {
                activeBadge
            } else {
                Button("Set Active") {
                    Task { await viewModel.setActive(.local, coordinator: coordinator) }
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// Compare by identity, not by full equality, so a remote still renders as
    /// "Active" during the brief window between `commitEditing` updating the
    /// remotes list and `coordinator.activeConnection` being rewritten with the
    /// fresh record. Without this the UI would flash "not active" mid-save.
    private func isActive(_ connection: HermesConnection) -> Bool {
        switch (coordinator.activeConnection, connection) {
        case (.local, .local): return true
        case (.remote(let a), .remote(let b)): return a.id == b.id
        default: return false
        }
    }

    private func remoteRow(_ remote: RemoteHermes) -> some View {
        VStack(spacing: 4) {
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "network")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(remote.nickname.isEmpty ? remote.host : remote.nickname)
                        .font(.body)
                    Text(remote.sshTarget + (remote.sshPort == 22 ? "" : ":\(remote.sshPort)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                testResultIndicator(for: remote)
                if isActive(.remote(remote)) {
                    activeBadge
                }
                rowMenu(for: remote)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var activeBadge: some View {
        Text("Active")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(.green.opacity(0.2)))
            .foregroundStyle(.green)
    }

    @ViewBuilder
    private func testResultIndicator(for remote: RemoteHermes) -> some View {
        if viewModel.testing == remote.id {
            ProgressView()
                .controlSize(.small)
        } else if let outcome = viewModel.testResults[remote.id] {
            Image(systemName: outcome.iconName)
                .foregroundStyle(outcome.isPassing ? .green : .red)
                .help(testResultMessage(outcome))
        }
    }

    private func testResultMessage(_ outcome: ConnectionsViewModel.TestOutcome) -> String {
        switch outcome {
        case .passed(let summary): return summary
        case .failed(let step, let msg): return "\(step): \(msg)"
        }
    }

    private func rowMenu(for remote: RemoteHermes) -> some View {
        Menu {
            if !isActive(.remote(remote)) {
                Button("Set Active") {
                    Task { await viewModel.setActive(.remote(remote), coordinator: coordinator) }
                }
            }
            Button("Test Connection") {
                Task { await viewModel.testConnection(remote) }
            }
            Button("Edit…") {
                viewModel.startEditing(remote)
            }
            Divider()
            Button("Remove…", role: .destructive) {
                viewModel.pendingDelete = remote
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var addButton: some View {
        HStack {
            Button {
                viewModel.startAddingRemote()
            } label: {
                Label("Add Remote Hermes", systemImage: "plus.circle")
            }
            .controlSize(.small)
            Spacer()
        }
    }
}

// MARK: - Edit Sheet

/// Form for adding a new remote or editing an existing one.
struct ConnectionEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator
    @Bindable var viewModel: ConnectionsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.isNewRemote ? "Add Remote Hermes" : "Edit Remote")
                .font(.title3.weight(.semibold))

            if let editing = Binding($viewModel.editing) {
                form(editing)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    viewModel.cancelEditing()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task {
                        await viewModel.commitEditing(coordinator: coordinator)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isFormValid)
            }
        }
        .padding(20)
    }

    private var isFormValid: Bool {
        guard let remote = viewModel.editing else { return false }
        return !remote.host.isEmpty && !remote.user.isEmpty && !remote.nickname.isEmpty
    }

    @ViewBuilder
    private func form(_ remote: Binding<RemoteHermes>) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
            fieldRow("Nickname", text: remote.nickname, hint: "Friendly name — shown in the picker + sidebar")
            fieldRow("Host", text: remote.host, hint: "Hostname or IP; must match ~/.ssh/known_hosts")
            fieldRow("User", text: remote.user)
            intRow("SSH Port", value: remote.sshPort)
            fieldRow("SSH Key", text: Binding(
                get: { remote.wrappedValue.sshKeyPath ?? "" },
                set: { remote.wrappedValue.sshKeyPath = $0.isEmpty ? nil : $0 }
            ), hint: "Optional — leave blank to use your default ssh-agent / ~/.ssh/config")
            fieldRow("Hermes Binary", text: remote.remoteBinaryPath, hint: "\"hermes\" on $PATH or an absolute path")
            fieldRow("HERMES_HOME", text: Binding(
                get: { remote.wrappedValue.remoteHermesHome ?? "" },
                set: { remote.wrappedValue.remoteHermesHome = $0.isEmpty ? nil : $0 }
            ), hint: "Optional — override the remote's ~/.hermes location")
        }
    }

    private func fieldRow(_ label: String, text: Binding<String>, hint: String? = nil) -> some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 110, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                TextField("", text: text)
                    .textFieldStyle(.roundedBorder)
                if let hint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func intRow(_ label: String, value: Binding<Int>) -> some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 110, alignment: .trailing)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 100, alignment: .leading)
        }
    }
}
