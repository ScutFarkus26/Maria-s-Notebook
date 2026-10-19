import SwiftUI

/// What the Resources screen lists, one type at a time.
nonisolated enum LibraryKind: String, CaseIterable, Identifiable, Sendable {
    case stories
    case packets
    case files
    case procedures

    var id: String { rawValue }

    /// The filter's label: a noun, no icon (HIG, segmented controls).
    var title: String {
        switch self {
        case .stories: return "Stories"
        case .packets: return "Packets"
        case .files: return "Files"
        case .procedures: return "Procedures"
        }
    }
}

/// The Resources screen: stories, book club packets, resource files and
/// written procedures, one type at a time, each on the shared
/// `PDFLibraryListView`. The type filter is a segmented control in the
/// toolbar on the Mac and tabs under the title on iPhone and iPad.
///
/// It sits at the Resources destination; the retired Stories and Procedures
/// rows open it on their own type (`NavigationItem.landing`).
struct ResourcesView: View {
    @Environment(\.appRouter) private var appRouter
    @State private var kind: LibraryKind

    init(kind: LibraryKind = .files) {
        _kind = State(initialValue: kind)
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            ViewHeader(title: "Resources")
            kindPicker
                .pickerStyle(.tabs)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            Divider()
            #endif
            list
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Resources")
        .onChange(of: appRouter.screenLanding, initial: true) { _, _ in
            if let landed = appRouter.consumeScreenLanding(where: { landing -> LibraryKind? in
                if case .resources(let kind) = landing { return kind }
                return nil
            }) {
                kind = landed
            }
        }
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .principal) {
                kindPicker
                    .pickerStyle(.segmented)
                    .fixedSize()
            }
        }
        #endif
    }

    private var kindPicker: some View {
        Picker("Show", selection: $kind) {
            ForEach(LibraryKind.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        }
        .labelsHidden()
    }

    @ViewBuilder
    private var list: some View {
        switch kind {
        case .stories: StoriesLibrary()
        case .packets: PacketsLibrary()
        case .files: FilesLibrary()
        case .procedures: ProceduresLibrary()
        }
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct ResourcesViewPreview: View {
    var body: some View {
        ResourcesView()
            .previewEnvironment()
    }
}

#Preview {
    ResourcesViewPreview()
}
