import SwiftUI
import WebKit

/// Signing in to ParentLocker, once per person: Email and Password (marked
/// as username and password, so the Passwords app may offer to fill them),
/// the privacy line, Sign In; and Sign Out once signed in. ParentLocker's own
/// page shows only when it asks for something more. Shared by the notebook's
/// Settings and the Daybook Assistant's classroom sheet.
struct ParentLockerSignInSheet: View {

    let sync: ParentLockerSync

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var session: ParentLockerSignIn?
    @State private var errorText: String?

    /// The privacy line under the fields (plan "ParentLocker attendance").
    nonisolated static let privacyLine =
        "Your password stays in your iCloud Keychain, encrypted by Apple, and is only used to sign in to ParentLocker."

    var body: some View {
        NavigationStack {
            Form {
                if sync.isSignedIn, session == nil {
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
                }
            }
            .formStyle(.grouped)
            .navigationTitle("ParentLocker")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sync.isSignedIn && session == nil ? "Done" : "Cancel") { close() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    private var signedIn: some View {
        Section {
            Label("Signed in to ParentLocker", systemImage: "checkmark.circle.fill")
            Button("Sign Out", role: .destructive) { sync.signOut() }
        } footer: {
            Text("Signing out here signs you out on your other devices too.")
        }
    }

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
        } footer: {
            Text(Self.privacyLine)
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
        Task {
            defer { session = nil }
            do {
                let cookies = try await attempt.run(credential, showsPagesWhenAsked: true)
                try await sync.completeSignIn(credential, cookies: cookies, site: attempt.host)
                password = ""
                dismiss()
            } catch ParentLockerSignInError.cancelled {
                return
            } catch {
                errorText = AppErrorMessages.userMessage(for: error, context: "signing in to ParentLocker")
            }
        }
    }

    private func close() {
        session?.cancel()
        dismiss()
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
