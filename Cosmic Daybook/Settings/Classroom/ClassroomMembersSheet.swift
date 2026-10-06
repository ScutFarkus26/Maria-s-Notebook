import SwiftUI
import CloudKit
import OSLog
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The Manage Sharing sheet, on every device: add people, send them the
/// classroom link, remove them.
///
/// Stands in for `UICloudSharingController`, which macOS doesn't have, and
/// which on iPhone and iPad always offers the owner a Stop Sharing that
/// deletes the share; see `ClassroomSharingService+Members` for both.
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
    #if os(macOS)
    /// Contacts whose name matches what's typed in the address field.
    @State private var suggestions: [ContactAddressSuggestion] = []
    #endif

    private static let loseAccessMessage =
        "They'll lose access to your students, attendance and school calendar. You can add them again later."

    private var members: [CKShare.Participant] {
        service.participants.filter { $0.role != .owner }
    }

    var body: some View {
        sheetLayout
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
                memberToRemove.map { "Remove \(ClassroomMemberRow.displayName($0)) from your classroom?" } ?? "",
                isPresented: Binding(
                    get: { memberToRemove != nil },
                    set: { if !$0 { memberToRemove = nil } }
                ),
                titleVisibility: .visible,
                presenting: memberToRemove
            ) { member in
                Button("Remove", role: .destructive) {
                    run("remove \(ClassroomMemberRow.displayName(member))") { try await service.removeMember(member) }
                }
            } message: { _ in
                Text(Self.loseAccessMessage)
            }
            #if os(macOS)
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
            #endif
    }

    /// A fixed-size sheet on the Mac; on iPhone and iPad it scrolls, so the
    /// keyboard never covers the list.
    @ViewBuilder
    private var sheetLayout: some View {
        #if os(macOS)
        content
            .padding(20)
            .frame(minWidth: 420, idealWidth: 480)
        #else
        ScrollView {
            content
                .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        #endif
    }

    private var content: some View {
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
            #if os(macOS)
            if !suggestions.isEmpty {
                ContactSuggestionList(suggestions: suggestions) { suggestion in
                    address = suggestion.address
                    suggestions = []
                }
            }
            #endif
            memberList
            if let url = service.currentShare?.url {
                ClassroomLinkRow(url: url)
            }

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
    }

    // MARK: - Add

    @ViewBuilder
    private var addForm: some View {
        #if os(macOS)
        HStack(spacing: AppTheme.Spacing.small) {
            addressField
            ContactPickerButton { picked in
                address = picked
                suggestions = []
            }
            .fixedSize()
            permissionPicker
            addButton
        }
        #else
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            addressField
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
            HStack(spacing: AppTheme.Spacing.small) {
                permissionPicker
                Spacer()
                addButton
                    .buttonStyle(.borderedProminent)
            }
        }
        #endif
    }

    private var addressField: some View {
        TextField("Email or phone number", text: $address)
            .textFieldStyle(.roundedBorder)
            .onSubmit(add)
    }

    private var permissionPicker: some View {
        Picker("Permission", selection: $permission) {
            Text("Can make changes").tag(CKShare.ParticipantPermission.readWrite)
            Text("View only").tag(CKShare.ParticipantPermission.readOnly)
        }
        .labelsHidden()
        .fixedSize()
    }

    private var addButton: some View {
        Button("Add", action: add)
            .keyboardShortcut(.defaultAction)
            .disabled(address.trimmed().isEmpty || isWorking)
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
                    ClassroomMemberRow(member: member, isWorking: isWorking) { memberToRemove = member }
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
                let ns = error as NSError
                Logger.cloudSharing.error(
                    "Couldn't \(action, privacy: .public): \(ns.domain, privacy: .public) \(ns.code, privacy: .public)"
                )
                errorMessage = AppErrorMessages.sharingMessage(for: error, action: action)
                // The share is gone: deleted on another device (an older
                // build's system sharing sheet). Stop showing it here.
                if case ClassroomSharingService.MemberError.noShare = error {
                    service.handleSharingStopped()
                }
            }
        }
    }
}

/// One person in the Manage Sharing sheet, with a button to remove them.
private struct ClassroomMemberRow: View {
    let member: CKShare.Participant
    let isWorking: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.circle.fill")
                .foregroundStyle(member.acceptanceStatus == .accepted ? AppColors.info : AppColors.warning)
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.displayName(member))
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove")
            .accessibilityLabel("Remove \(Self.displayName(member))")
            .disabled(isWorking)
        }
    }

    static func displayName(_ member: CKShare.Participant) -> String {
        if let name = member.userIdentity.nameComponents {
            let formatted = PersonNameComponentsFormatter.localizedString(from: name, style: .default).trimmed()
            if !formatted.isEmpty { return formatted }
        }
        let lookup = member.userIdentity.lookupInfo
        return lookup?.emailAddress ?? lookup?.phoneNumber ?? "Name not shared"
    }

    private var statusLine: String {
        let status = member.acceptanceStatus == .accepted ? "Joined" : "Invited"
        let access = member.permission == .readWrite ? "Can make changes" : "View only"
        return "\(status) · \(access)"
    }
}

/// The classroom link: copy it, or send it (Messages, Mail…).
private struct ClassroomLinkRow: View {
    let url: URL

    @State private var linkCopied = false
    /// Puts "Copy link" back a moment after a copy; replaced by each new copy.
    @State private var linkCopiedReset: Task<Void, Never>?

    var body: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Button {
                copy()
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
        .onDisappear { linkCopiedReset?.cancel() }
    }

    private func copy() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #else
        UIPasteboard.general.url = url
        #endif
    }
}
