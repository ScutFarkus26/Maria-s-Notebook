import SwiftUI
import WebKit

/// Signing in to ParentLocker, once per person: the school's site, Email and
/// Password (marked as username and password, so the Passwords app may offer
/// to fill them), Sign In, then what happens when you sign in, in plain
/// words; and Sign Out once signed in. ParentLocker's own page shows only
/// when it asks for something more. Shared by the notebook's Settings and the
/// Daybook Assistant's classroom sheet, so its words fit both. Sign In comes
/// straight after the fields, so it stays in reach above the keyboard on an
/// iPhone SE, and the notice below it scrolls.
struct ParentLockerSignInSheet: View {

    let sync: ParentLockerSync

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var session: ParentLockerSignIn?
    /// The sign-in under way: closing the sheet cancels it, the final check
    /// of the class list included, so nothing is kept.
    @State private var signInTask: Task<Void, Never>?
    @State private var errorText: String?

    nonisolated static let title = "Sign in to ParentLocker"
    nonisolated static let onceLine = "You only need to do this once. After that, the app stays signed in for you."
    nonisolated static let noticeTitle = "What happens when you sign in"
    /// The privacy notice, a line each, each with its symbol. Kept true to
    /// the engine: the sign-in fills the site's own form; the password is a
    /// synced Keychain item, never in Core Data, backups or the share; the
    /// planner sends the mark, an absence's reason and a left-early time, and
    /// never the written attendance note; a sync signed out signs in again;
    /// Sign Out deletes the synced password everywhere.
    nonisolated static let notice: [(symbol: String, text: String)] = [
        ("person.badge.key", "The app signs in to ParentLocker for you, the same way you would on the website."),
        ("lock.icloud", "Your password is saved in your iCloud Keychain, which Apple encrypts. "
            + "Only your own devices can read it. It's never stored in the app or its backups, "
            + "and none of your co-workers can see it or use it."),
        ("checklist", "It's used only to send the attendance you take: who is here, late or absent, "
            + "why a child is absent, and when a child left early. Notes you write about a child aren't sent."),
        ("arrow.clockwise", "If ParentLocker signs you out, the app signs back in by itself."),
        ("rectangle.portrait.and.arrow.right", "Signing out deletes the saved password from all your devices.")
    ]

    var body: some View {
        NavigationStack {
            Form {
                if showsSignedIn {
                    signedIn
                } else {
                    fields
                    if let session, session.phase == .needsYou, let webView = session.webView {
                        Section {
                            ParentLockerWebView(webView: webView)
                                .frame(minHeight: 440)
                        } header: {
                            Text("ParentLocker needs you to finish signing in.")
                        }
                    }
                    noticeSection
                }
            }
            .formStyle(.grouped)
            .navigationTitle(showsSignedIn ? "ParentLocker" : Self.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(showsSignedIn ? "Done" : "Cancel") { close() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
        // However the sheet goes (a swipe down too), a sign-in under way stops.
        .onDisappear { stopSigningIn() }
    }

    /// Signed in, with a password ParentLocker still takes: otherwise (it
    /// refused the saved one) the fields show, to sign in again.
    private var showsSignedIn: Bool {
        sync.isSignedIn && !sync.savedPasswordRefused && session == nil
    }

    /// Above the fields: the school's site, small, and that this happens
    /// once. Capped at the first accessibility size, so at the largest text
    /// the fields and Sign In still come into view on an iPhone SE; the site
    /// shrinks to one line rather than break.
    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(sync.site, systemImage: "building.columns")
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel("School site, \(sync.site)")
            Text(Self.onceLine)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textCase(nil)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.bottom, 4)
    }

    /// "What happens when you sign in": a short line for each point.
    private var noticeSection: some View {
        Section {
            ForEach(Self.notice, id: \.text) { line in
                Label {
                    Text(line.text)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: line.symbol)
                        .foregroundStyle(.tint)
                }
            }
        } header: {
            Text(Self.noticeTitle)
        }
    }

    private var signedIn: some View {
        Section {
            Label("Signed in to ParentLocker", systemImage: "checkmark.circle.fill")
            Button("Sign Out", role: .destructive, action: signOut)
            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
            }
        } footer: {
            Text("Signing out here signs you out on your other devices too.")
        }
    }

    /// Shows signed out only once the saved password is really gone.
    private func signOut() {
        do {
            try sync.signOut()
            errorText = nil
        } catch {
            errorText = Self.signOutFailed
        }
    }

    nonisolated static let signOutFailed = "Couldn't sign out of ParentLocker on this device. Try again."

    @ViewBuilder
    private var fields: some View {
        Section {
            TextField("Email", text: $email)
                .textContentType(.username)
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textContentType(.password)
                .onSubmit(signIn)
        } header: {
            intro
        }
        if let errorText {
            Section {
                Text(errorText)
                    .foregroundStyle(.red)
            }
        }
        Section {
            if session != nil {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Signing in…")
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Sign In", action: signIn)
                    .disabled(!canSignIn)
            }
        }
    }

    private var canSignIn: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func signIn() {
        guard canSignIn, session == nil else { return }
        errorText = nil
        let credential = ParentLockerKeychain.Credential(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password
        )
        let attempt = ParentLockerSignIn(site: sync.site)
        session = attempt
        signInTask = Task {
            defer {
                session = nil
                signInTask = nil
            }
            do {
                let cookies = try await attempt.run(credential, showsPagesWhenAsked: true)
                // Closed while the last page loaded: nothing is kept.
                guard !attempt.isCancelled, !Task.isCancelled else { return }
                try await sync.completeSignIn(credential, cookies: cookies, site: attempt.host)
                password = ""
                dismiss()
            } catch ParentLockerSignInError.cancelled {
                return
            } catch {
                // Closed meanwhile: a cancelled request says nothing to anyone.
                guard !attempt.isCancelled, !Task.isCancelled else { return }
                errorText = AppErrorMessages.userMessage(for: error, context: "signing in to ParentLocker")
            }
        }
    }

    private func close() {
        stopSigningIn()
        dismiss()
    }

    private func stopSigningIn() {
        session?.cancel()
        signInTask?.cancel()
    }
}

// MARK: - ParentLocker's own page, when it asks for more

#if os(macOS)
/// The sign-in's web view, shown only when ParentLocker asks for something more.
struct ParentLockerWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
/// The sign-in's web view, shown only when ParentLocker asks for something more.
struct ParentLockerWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
