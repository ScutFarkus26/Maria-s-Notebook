import SwiftUI
import CoreData

// The ParentLocker live check without Settings (plan "ParentLocker
// attendance", Phase 2b): launch the notebook's Debug Mac app with
// `-ParentLockerPreview YES` and, once the notebook is open, a sheet signs in
// if this Mac isn't yet, then shows today's preview: each class, the
// children matched, the marks it would send and what it leaves alone. The
// same text goes to standard output, for a run from Terminal. Read only: a
// Debug build never saves to ParentLocker (`ParentLockerSavePolicy`) and a
// preview writes nothing, matches included. Notebook only; Release builds
// compile none of it.

extension View {
    /// Shows the ParentLocker preview on launch when asked for (Debug, Mac only).
    func parentLockerPreviewOnLaunch(context: NSManagedObjectContext) -> some View {
        #if DEBUG && os(macOS)
        modifier(ParentLockerPreviewLaunch(context: context))
        #else
        self
        #endif
    }
}

#if DEBUG && os(macOS)

/// Opens the preview sheet once per process, on the first window.
private struct ParentLockerPreviewLaunch: ViewModifier {

    let context: NSManagedObjectContext

    @State private var sync: ParentLockerSync?

    static let argument = "-ParentLockerPreview"
    @MainActor private static var opened = false

    /// `-ParentLockerPreview`, alone or followed by YES, true or 1.
    static func isRequested(in arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        guard let flag = arguments.firstIndex(of: argument) else { return false }
        guard arguments.indices.contains(flag + 1), !arguments[flag + 1].hasPrefix("-") else { return true }
        return ["yes", "true", "1"].contains(arguments[flag + 1].lowercased())
    }

    func body(content: Content) -> some View {
        content
            .task {
                guard Self.isRequested(), !Self.opened else { return }
                Self.opened = true
                // Not started: nothing is watched, and the app's own sync stays `current`.
                let preview = ParentLockerSync(context: context)
                preview.refreshSignIn()
                sync = preview
            }
            .sheet(item: Binding(get: { sync.map(PreviewItem.init) }, set: { if $0 == nil { sync = nil } })) { item in
                ParentLockerPreviewSheet(sync: item.sync)
            }
    }

    private struct PreviewItem: Identifiable {
        let sync: ParentLockerSync
        var id: ObjectIdentifier { ObjectIdentifier(sync) }
    }
}

/// Today's preview, with Sign In first when needed.
private struct ParentLockerPreviewSheet: View {

    let sync: ParentLockerSync

    @Environment(\.dismiss) private var dismiss
    @State private var text = "Reading ParentLocker…"
    @State private var isRunning = false
    @State private var showsSignIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ParentLocker preview (nothing is sent)")
                .font(.headline)
            ScrollView {
                Text(text)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button(sync.isSignedIn ? "Sign Out" : "Sign In") {
                    if sync.isSignedIn { sync.signOut() } else { showsSignIn = true }
                }
                Spacer()
                Button("Preview Again") { Task { await preview() } }
                    .disabled(isRunning || !sync.isSignedIn)
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 460)
        .sheet(isPresented: $showsSignIn) { ParentLockerSignInSheet(sync: sync) }
        .task {
            if sync.isSignedIn { await preview() } else { showsSignIn = true }
        }
        .onChange(of: sync.isSignedIn) { _, signedIn in
            if signedIn { Task { await preview() } } else { text = "Signed out." }
        }
    }

    private func preview() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        text = "Reading ParentLocker…"
        switch await sync.send(day: sync.today, preview: true) {
        case .success(let report):
            text = report.text
        case .failure(let failure):
            text = failure.message
        }
        print("[ParentLockerPreview]\n\(text)")
    }
}

#endif
