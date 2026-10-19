import SwiftUI

/// Settings › Connections › Tide: the connection address, where new to-dos
/// go, which Tide lists show here, the switch, and the first run's matches.
/// On iPhone and iPad it says the Mac does the sharing.
struct TideSyncSettingsView: View {
    @State private var service = TideSyncService.shared
    @State private var addressText = ""
    @State private var addressProblem: String?
    @State private var isEditingAddress = false
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
            if service.policy == .live {
                macContent
            } else {
                Text(service.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(TideSyncMessages.explainer)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .task {
            if service.policy == .live, service.hasAddress { await service.refreshLists(quietly: true) }
        }
    }

    @ViewBuilder private var macContent: some View {
        status

        if service.hasAddress && !isEditingAddress {
            connected
        } else {
            addressEntry
        }

        if service.hasAddress {
            Toggle("Share to-dos with Tide", isOn: $service.settings.isOn)
            if let proposal = service.proposal {
                TideFirstRunReview(proposal: proposal) { kept in
                    Task { await service.confirmFirstRun(kept) }
                }
            }
            if !service.lists.isEmpty {
                destinationPickers
                shownLists
            }
            SyncActionButtons(
                refreshLabel: "Refresh lists",
                isSyncDisabled: !service.settings.isOn || service.isSyncing,
                isRefreshing: service.isSyncing || isWorking,
                onRefresh: { Task { await service.refreshLists() } },
                onSync: { Task { await service.syncNow() } }
            )
            LastSyncView(lastSync: service.lastSyncAt)
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 4) {
            StatusMessageView(status: service.statusIsProblem
                ? .failure(service.statusMessage)
                : .info(service.statusMessage))
            if let details = service.statusDetails {
                TechnicalDetailsDisclosure(details: details)
            }
        }
    }

    private var connected: some View {
        HStack {
            Label("Connected to Tide on this Mac", systemImage: "checkmark.circle")
                .font(.subheadline)
            Spacer()
            Button("Change Address…") {
                addressText = ""
                addressProblem = nil
                isEditingAddress = true
            }
            Button("Forget", role: .destructive) { service.forgetAddress() }
        }
    }

    private var addressEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tide's connection address")
                .font(.subheadline.weight(.semibold))
            HStack {
                TextField("Paste the address from Tide's Settings › Claude", text: $addressText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit(connect)
                Button("Connect", action: connect)
                    .disabled(addressText.trimmed().isEmpty || isWorking)
                if isEditingAddress {
                    Button("Cancel") { isEditingAddress = false }
                }
            }
            if let addressProblem {
                StatusMessageView(status: .failure(addressProblem))
            }
        }
    }

    private func connect() {
        let text = addressText
        isWorking = true
        Task {
            addressProblem = await service.saveAddress(text)
            isWorking = false
            if addressProblem == nil {
                addressText = ""
                isEditingAddress = false
            }
        }
    }

    @ViewBuilder private var destinationPickers: some View {
        Picker("New to-dos go to", selection: $service.settings.destinationFile) {
            ForEach(service.lists, id: \.file) { list in
                Text(list.name).tag(list.file)
            }
            if !service.lists.contains(where: { $0.file == service.settings.destinationFile }) {
                Text(TideActionLink.listName(ofFile: service.settings.destinationFile))
                    .tag(service.settings.destinationFile)
            }
        }
        let headings = service.headings[service.settings.destinationFile] ?? []
        if !headings.isEmpty {
            Picker("Under the heading", selection: $service.settings.destinationHeading) {
                Text("The list's first heading").tag(String?.none)
                ForEach(headings, id: \.self) { heading in
                    Text(heading).tag(String?.some(heading))
                }
            }
        }
    }

    private var shownLists: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Show in the notebook")
                .font(.subheadline.weight(.semibold))
            ForEach(service.lists, id: \.file) { list in
                Toggle(list.name, isOn: Binding(
                    get: { service.settings.shows(list.file) },
                    set: { isOn in
                        var shown = service.settings.shownLists ?? Set(service.lists.map(\.file))
                        if isOn { shown.insert(list.file) } else { shown.remove(list.file) }
                        let everything = Set(service.lists.map(\.file))
                        service.settings.shownLists = shown == everything ? nil : shown
                    }
                ))
            }
        }
    }
}

/// The first run: which notebook to-dos look like ones already in Tide.
/// Nothing is linked or sent until Danny presses Link and Start.
private struct TideFirstRunReview: View {
    let proposal: TideFirstRunProposal
    let onConfirm: ([TideFirstRunProposal.Match]) -> Void
    @State private var dropped: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Already in both")
                .font(.subheadline.weight(.semibold))
            if proposal.matches.isEmpty {
                Text("None of the notebook's to-dos look like ones already in Tide.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(proposal.matches) { match in
                Toggle(isOn: Binding(
                    get: { !dropped.contains(match.id) },
                    set: { keep in
                        if keep { dropped.remove(match.id) } else { dropped.insert(match.id) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(match.notebookTitle)
                        Text("Tide, \(match.listName): \(match.tideText)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if match.isCheckIn {
                            Text("A work check-in: linked, so a tick in either app ticks the other.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Link and Start") {
                onConfirm(proposal.matches.filter { !dropped.contains($0.id) })
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// What happens to the rest: unticked pairs count as different to-dos (a
    /// work check-in stays here).
    private var summary: String {
        let droppedMatches = proposal.matches.filter { dropped.contains($0.id) }
        let toSend = proposal.toSend + droppedMatches.filter { !$0.isCheckIn }.count
        let toShow = proposal.toShow + droppedMatches.count
        let sent = toSend == 1 ? "1 notebook to-do goes" : "\(toSend) notebook to-dos go"
        let shown = toShow == 1 ? "1 Tide to-do shows" : "\(toShow) Tide to-dos show"
        return "Ticked pairs are linked as one to-do. Then \(sent) to Tide's \(proposal.destinationName) list, "
            + "and \(shown) here."
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct TideSyncSettingsViewPreview: View {
    var body: some View {
        TideSyncSettingsView()
            .padding()
    }
}

#Preview {
    TideSyncSettingsViewPreview()
}
