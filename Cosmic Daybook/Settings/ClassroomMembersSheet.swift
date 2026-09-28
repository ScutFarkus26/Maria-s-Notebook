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
    let onDone: () -> Void

    @State private var address = ""
    @State private var permission: CKShare.ParticipantPermission = .readWrite
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var confirmingRemoveAll = false
    @State private var linkCopied = false

    private var members: [CKShare.Participant] {
        service.participants.filter { $0.role != .owner }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Share Classroom")
                    .font(.title2.weight(.semibold))
                Text(
                    "Add your assistant by the email address or phone number of their Apple Account, " +
                    "then send them the link. The link only opens for people added here."
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            addForm
            memberList
            linkRow

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if !members.isEmpty {
                    Button("Remove Everyone…", role: .destructive) {
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
        .frame(width: 480)
        .confirmationDialog(
            "Remove everyone from your classroom?",
            isPresented: $confirmingRemoveAll,
            titleVisibility: .visible
        ) {
            Button("Remove Everyone", role: .destructive) {
                run("removing classroom members") { try await service.removeAllMembers() }
            }
        } message: {
            Text("Assistants will lose access to classroom data. You can add them again later.")
        }
    }

    // MARK: - Add

    private var addForm: some View {
        HStack(spacing: 8) {
            TextField("Email or phone number", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
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
        run("adding \(entered.trimmed())") {
            try await service.addMember(entered, permission: permission)
            address = ""
        }
    }

    // MARK: - Members

    private var memberList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("People")
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
                .foregroundStyle(member.acceptanceStatus == .accepted ? .blue : .yellow)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName(member))
                Text(statusLine(member))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                run("removing \(displayName(member))") { try await service.removeMember(member) }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove")
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
        let access = member.permission == .readWrite ? "can make changes" : "view only"
        return "\(status) · \(access)"
    }

    // MARK: - Link

    @ViewBuilder
    private var linkRow: some View {
        if let url = service.currentShare?.url {
            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    linkCopied = true
                } label: {
                    Label(linkCopied ? "Link Copied" : "Copy Link", systemImage: "link")
                }
                ShareLink(item: url) {
                    Label("Send Link…", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: - Work

    private func run(_ context: String, _ work: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                try await work()
            } catch {
                errorMessage = AppErrorMessages.userMessage(for: error, context: context)
            }
        }
    }
}
#endif
