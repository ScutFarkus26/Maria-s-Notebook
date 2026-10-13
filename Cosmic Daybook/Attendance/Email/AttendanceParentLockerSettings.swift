import SwiftUI

/// Settings › Messages › Attendance to the School, with ParentLocker picked
/// (plan "ParentLocker attendance", Phase 3): the school's ParentLocker
/// address, signing in and out (the shared sheet), and Match Names. Nothing
/// of the sign-in shows here but whether there is one. Notebook only.
struct AttendanceParentLockerSettings: View {

    /// The school's ParentLocker address, as the guide typed it.
    @Binding var site: String

    @Environment(\.managedObjectContext) private var viewContext
    @State private var showsSignIn = false

    var body: some View {
        let sync = ParentLockerSync.current(for: viewContext)
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("School's ParentLocker address") {
                TextField(AttendanceEmailLog.defaultParentLockerSite, text: $site)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #else
                    .frame(minWidth: 220)
                    #endif
            }
            if let sync {
                signInRow(sync)
                NavigationLink {
                    ParentLockerMatchView(sync: sync)
                        .settingsBreadcrumb("Settings › Messages")
                } label: {
                    SettingsLinkRow(title: "Match Names", systemImage: "person.2.badge.gearshape")
                }
                .buttonStyle(.plain)
                .disabled(!sync.isSignedIn)
                Text(Self.footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Open your own class, not the Sample Class, to sign in to ParentLocker.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showsSignIn) {
            if let sync { ParentLockerSignInSheet(sync: sync) }
        }
    }

    private func signInRow(_ sync: ParentLockerSync) -> some View {
        LabeledContent("Your ParentLocker sign-in") {
            HStack(spacing: 8) {
                Label(
                    sync.isSignedIn ? "Signed in" : "Not signed in",
                    systemImage: sync.isSignedIn ? "checkmark.circle.fill" : "person.crop.circle.badge.questionmark"
                )
                .foregroundStyle(sync.isSignedIn ? Color.green : Color.secondary)
                Button(sync.isSignedIn ? "Sign Out…" : "Sign In…") { showsSignIn = true }
            }
        }
    }

    static let footnote = "Sign in once with your own ParentLocker account; it covers your other devices too. "
        + "Each assistant signs in once on her phone with her own. Close Arrival sends the class, and "
        + "every change after that follows by itself. Match Names lists any child the app couldn't find "
        + "in ParentLocker by name."
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct AttendanceParentLockerSettingsPreview: View {
    @State private var site = ""
    var body: some View {
        NavigationStack {
            AttendanceParentLockerSettings(site: $site)
                .padding()
        }
    }
}

#Preview {
    AttendanceParentLockerSettingsPreview()
}
