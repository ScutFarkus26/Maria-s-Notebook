import SwiftUI

/// Settings › Messages › Attendance to the School, with ParentLocker picked
/// (plan "ParentLocker attendance", Phase 3): the school's ParentLocker
/// address, signing in and out (the shared sheet), and Match Names. Nothing
/// of the sign-in shows here but whether there is one. Notebook only.
struct AttendanceParentLockerSettings: View {

    /// The school's ParentLocker address: the shared row's, or what's being typed.
    @Binding var site: String
    /// Puts the typed address into the share: on Return, and before the
    /// sign-in sheet opens, so the sheet signs in to the address shown (bug
    /// hunt 2026-10-13 afternoon, L3). Typing alone writes nothing.
    var commitSite: () -> Void = {}

    @Environment(\.managedObjectContext) private var viewContext
    @State private var showsSignIn = false

    var body: some View {
        let sync = ParentLockerSync.current(for: viewContext)
        VStack(alignment: .leading, spacing: 12) {
            AttendanceSettingRow(
                "School's ParentLocker address", stacksWhenCompact: true, stacksWhenNarrow: false
            ) { _ in
                TextField(AttendanceEmailLog.defaultParentLockerSite, text: $site)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
                    .onSubmit(commitSite)
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
        .sheet(isPresented: $showsSignIn, onDismiss: {
            // Closed without signing in: a send waiting for it doesn't ask
            // again by itself, and a Send Now waiting for it is dropped.
            if let sync, sync.needsSignIn { sync.signInDismissed() }
        }, content: {
            if let sync { ParentLockerSignInSheet(sync: sync) }
        })
    }

    private func signInRow(_ sync: ParentLockerSync) -> some View {
        // Signed in and working, or not: never signed in here, ParentLocker
        // refused the saved password, or it asks for a sign-in again (new
        // terms, a reset): then the button is Sign In.
        let working = !sync.needsSignIn
        let status = Label(
            Self.signInTitle(isSignedIn: sync.isSignedIn, needsSignIn: sync.needsSignIn),
            systemImage: working ? "checkmark.circle.fill" : "person.crop.circle.badge.questionmark"
        )
        .foregroundStyle(working ? Color.green : Color.secondary)
        let button = Button(Self.signInButtonTitle(needsSignIn: sync.needsSignIn)) {
            commitSite()
            showsSignIn = true
        }
        return AttendanceSettingRow("Your ParentLocker sign-in", stacksWhenCompact: true) { _ in
            // Side by side when they fit, else the button under the words.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { status; button }
                VStack(alignment: .leading, spacing: 6) { status; button }
            }
        }
    }

    /// What the sign-in row says (bug hunt 2026-10-13 afternoon, M9): signed
    /// in and working; signed in, but ParentLocker needs a sign-in again
    /// (`needsSignIn`: it refused the saved password, or asks again after new
    /// terms or a reset); or not signed in.
    static func signInTitle(isSignedIn: Bool, needsSignIn: Bool) -> String {
        guard needsSignIn else { return "Signed in" }
        return isSignedIn ? "Sign in again" : "Not signed in"
    }

    /// The row's button: Sign In whenever ParentLocker needs one.
    static func signInButtonTitle(needsSignIn: Bool) -> String {
        needsSignIn ? "Sign In…" : "Sign Out…"
    }

    static let footnote = "Sign in once with your own ParentLocker account; it covers your other devices too. "
        + "Each assistant signs in once on her phone with her own. Close Arrival & Send sends the class, and "
        + "later changes follow by themselves. Match Names lists any child the app couldn't find "
        + "in ParentLocker by name."
}

/// "Send attendance by": ParentLocker or the front-desk email. A menu beside
/// its name; above it, where the menu's own button clipped its words at the
/// largest text sizes (L7), a menu whose words wrap.
struct AttendanceSendMethodPicker: View {
    @Binding var method: AttendanceSendMethod

    private static let title = "Send attendance by"

    private static func name(_ method: AttendanceSendMethod) -> String {
        switch method {
        case .parentLocker: "ParentLocker"
        case .email: "Email to the front desk"
        }
    }

    private var choices: some View {
        Picker(Self.title, selection: $method) {
            ForEach([AttendanceSendMethod.parentLocker, .email], id: \.self) { method in
                Text(Self.name(method)).tag(method)
            }
        }
        .labelsHidden()
    }

    var body: some View {
        AttendanceSettingRow(Self.title) { stacked in
            if stacked {
                Menu {
                    choices.pickerStyle(.inline)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Self.name(method))
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.up.chevron.down")
                            .imageScale(.small)
                    }
                }
            } else {
                choices.fixedSize()
            }
        }
    }
}

/// A setting's name beside its control, or above it where beside it the
/// control ran off an iPhone's screen (bug hunt 2026-10-13 afternoon, L7):
/// at the accessibility text sizes, and whenever the two don't fit side by
/// side. `stacksWhenCompact` puts it above on an iPhone at every size, for a
/// field too cramped beside its name on an iPhone SE. The control is told
/// which, so it can lay itself out to fit.
struct AttendanceSettingRow<Control: View>: View {
    let title: String
    let stacksWhenCompact: Bool
    /// Off for a text field, whose width changes as it's typed in: the row
    /// would move it mid-word, and the keyboard would go.
    let stacksWhenNarrow: Bool
    let control: (_ stacked: Bool) -> Control

    @Environment(\.dynamicTypeSize) private var typeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    init(
        _ title: String, stacksWhenCompact: Bool = false, stacksWhenNarrow: Bool = true,
        @ViewBuilder control: @escaping (_ stacked: Bool) -> Control
    ) {
        self.title = title
        self.stacksWhenCompact = stacksWhenCompact
        self.stacksWhenNarrow = stacksWhenNarrow
        self.control = control
    }

    private var stacked: Bool {
        #if os(iOS)
        if stacksWhenCompact, sizeClass == .compact { return true }
        #endif
        return typeSize.isAccessibilitySize
    }

    var body: some View {
        if stacked {
            stackedRow
        } else if stacksWhenNarrow {
            ViewThatFits(in: .horizontal) {
                LabeledContent(title) { control(false) }
                stackedRow
            }
        } else {
            LabeledContent(title) { control(false) }
        }
    }

    private var stackedRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            control(true)
        }
    }
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
