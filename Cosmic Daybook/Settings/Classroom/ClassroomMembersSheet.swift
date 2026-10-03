#if os(macOS)
import SwiftUI
import CloudKit
import AppKit

/// The Mac's Manage Sharing sheet: add people, send them the classroom link,
/// remove them.
///
/// Stands in for `UICloudSharingController`, which macOS doesn't have; see
/// `ClassroomSharingService+Members` for why the system share popover isn't
/// used.
struct ClassroomMembersSheet: View {
    let service: ClassroomSharingService
    /// What the classroom share holds, checked before this sheet opens.
    let contents: ClassroomShareContents?
    let onDone: () -> Void

    @State private var address = ""
    @State private var permission: CKShare.ParticipantPermission = .readWrite
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var confirmingRemoveAll = false
    /// The person whose minus button was clicked, waiting for the confirmation.
    @State private var memberToRemove: CKShare.Participant?
    @State private var linkCopied = false
    /// Puts "Copy link" back a moment after a copy; replaced by each new copy.
    @State private var linkCopiedReset: Task<Void, Never>?
    /// Contacts whose name matches what's typed in the address field.
    @State private var suggestions: [ContactAddressSuggestion] = []

    private static let loseAccessMessage =
        "They'll lose access to your students, attendance and school calendar. You can add them again later."

    private var members: [CKShare.Participant] {
        service.participants.filter { $0.role != .owner }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                Text("Share your classroom")
                    .font(.title2.weight(.semibold))
                Text(
                    "Add your assistant by the email address or phone number of their Apple Account, " +
                    "then send them the link. The link only opens for people added here."
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let contents {
                    Label("What your assistant sees: \(contents.summary).", systemImage: "eye")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            addForm
            if !suggestions.isEmpty {
                ContactSuggestionList(suggestions: suggestions) { suggestion in
                    address = suggestion.address
                    suggestions = []
                }
            }
            memberList
            linkRow

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(AppColors.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if !members.isEmpty {
                    Button("Remove everyone…", role: .destructive) {
                        confirmingRemoveAll = true
                    }
                    .disabled(isWorking)
                }
                Spacer()
                if isWorking {
                    ProgressView().controlSize(.small)
                }
                Button("Done", action: onDone)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 480)
        .confirmationDialog(
            "Remove everyone from your classroom?",
            isPresented: $confirmingRemoveAll,
            titleVisibility: .visible
        ) {
            Button("Remove everyone", role: .destructive) {
                run("remove everyone") { try await service.removeAllMembers() }
            }
        } message: {
            Text(Self.loseAccessMessage)
        }
        .confirmationDialog(
            memberToRemove.map { "Remove \(displayName($0)) from your classroom?" } ?? "",
            isPresented: Binding(
                get: { memberToRemove != nil },
                set: { if !$0 { memberToRemove = nil } }
            ),
            titleVisibility: .visible,
            presenting: memberToRemove
        ) { member in
            Button("Remove", role: .destructive) {
                run("remove \(displayName(member))") { try await service.removeMember(member) }
            }
        } message: { _ in
            Text(Self.loseAccessMessage)
        }
        .onDisappear { linkCopiedReset?.cancel() }
        .task {
            // Ask here, where the reason is on screen, rather than mid-typing.
            _ = await ContactAddressBook.requestAccess()
        }
        .task(id: address) {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let found = await ContactAddressBook.suggestions(matching: address)
            guard !Task.isCancelled else { return }
            suggestions = found
        }
    }

    // MARK: - Add

    private var addForm: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            TextField("Email or phone number", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            ContactPickerButton { picked in
                address = picked
                suggestions = []
            }
            .fixedSize()
            Picker("Permission", selection: $permission) {
                Text("Can make changes").tag(CKShare.ParticipantPermission.readWrite)
                Text("View only").tag(CKShare.ParticipantPermission.readOnly)
            }
            .labelsHidden()
            .fixedSize()
            Button("Add", action: add)
                .keyboardShortcut(.defaultAction)
                .disabled(address.trimmed().isEmpty || isWorking)
        }
    }

    private func add() {
        let entered = address
        guard !entered.trimmed().isEmpty else { return }
        run("add \(entered.trimmed())") {
            try await service.addMember(entered, permission: permission)
            address = ""
        }
    }

    // MARK: - Members

    private var memberList: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
            Text("Members")
                .font(.headline)
            if members.isEmpty {
                Text("Nobody else yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(members, id: \.participantID) { member in
                    memberRow(member)
                }
            }
        }
    }

    private func memberRow(_ member: CKShare.Participant) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.circle.fill")
                .foregroundStyle(member.acceptanceStatus == .accepted ? AppColors.info : AppColors.warning)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName(member))
                Text(statusLine(member))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                memberToRemove = member
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove")
            .accessibilityLabel("Remove \(displayName(member))")
            .disabled(isWorking)
        }
    }

    private func displayName(_ member: CKShare.Participant) -> String {
        if let name = member.userIdentity.nameComponents {
            let formatted = PersonNameComponentsFormatter.localizedString(from: name, style: .default).trimmed()
            if !formatted.isEmpty { return formatted }
        }
        let lookup = member.userIdentity.lookupInfo
        return lookup?.emailAddress ?? lookup?.phoneNumber ?? "Name not shared"
    }

    private func statusLine(_ member: CKShare.Participant) -> String {
        let status = member.acceptanceStatus == .accepted ? "Joined" : "Invited"
        let access = member.permission == .readWrite ? "Can make changes" : "View only"
        return "\(status) · \(access)"
    }

    // MARK: - Link

    @ViewBuilder
    private var linkRow: some View {
        if let url = service.currentShare?.url {
            HStack(spacing: AppTheme.Spacing.small) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    linkCopied = true
                    linkCopiedReset?.cancel()
                    linkCopiedReset = Task {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        linkCopied = false
                    }
                } label: {
                    Label(linkCopied ? "Link copied" : "Copy link", systemImage: "link")
                }
                ShareLink(item: url) {
                    Label("Send link…", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: - Work

    /// Runs a sharing change; `action` finishes "Couldn't …" ("add Sam").
    private func run(_ action: String, _ work: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                try await work()
            } catch {
                errorMessage = AppErrorMessages.sharingMessage(for: error, action: action)
            }
        }
    }
}
#endif
