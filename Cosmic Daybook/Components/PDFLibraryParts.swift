import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

/// One titled run of cards in a `PDFLibraryListView` grid ("Writing Papers").
/// A section with no title draws no heading.
struct PDFLibrarySection<Item: NSManagedObject>: Identifiable {
    let title: String?
    var systemImage: String?
    /// A line under the title ("Fire drills, lockdowns, medical emergencies").
    var subtitle: String?
    let items: [Item]

    var id: String { title ?? "" }
}

/// The open card's object, as a sheet's item.
struct PDFLibrarySelectedObject: Identifiable {
    let id: NSManagedObjectID
}

/// A section's heading in a `PDFLibraryListView` grid: icon, title, an
/// optional line under it, and the count.
struct PDFLibrarySectionHeading: View {
    let title: String
    let systemImage: String?
    let subtitle: String?
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// What a `PDFLibraryListView` shows while a PDF is dragged over it.
struct PDFLibraryDropOverlay: View {
    let prompt: String

    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.08)
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                Text(prompt)
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Off-main-actor support for dropped PDFs. Kept outside the generic view so the
/// `@Sendable` load-completion closure captures no generic metatypes.
enum PDFDropSupport {
    /// Copies a dropped PDF into a folder of its own in tmp, under its own
    /// name: the import titles the story, packet or resource (and names its
    /// file) after it. Nil when it couldn't be copied.
    nonisolated static func copyToTempIfNeeded(_ url: URL, logger: Logger) -> URL? {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let temp = folder.appendingPathComponent(url.lastPathComponent, isDirectory: false)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try fm.copyItem(at: url, to: temp)
            return temp
        } catch {
            logger.warning("Failed to copy dropped PDF to temp: \(error.localizedDescription, privacy: .public)")
            try? fm.removeItem(at: folder)
            return nil
        }
    }

    /// Imports a dropped PDF's temp copy with `importPDF` (which copies it into
    /// the library), then removes the copy and its folder. Returns the import's
    /// message, nil when it worked.
    static func importTempCopy(_ copy: URL, using importPDF: (URL) -> String?) -> String? {
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        return importPDF(copy)
    }
}

/// The empty state of a `PDFLibraryListView`: one message when the library has
/// nothing at all, another (with a "Clear filters" button) when the filters hide
/// everything. `footer` renders under the hint only while the library is empty.
struct PDFLibraryEmptyState<Footer: View>: View {
    let systemImage: String
    let isLibraryEmpty: Bool
    let emptyTitle: String
    let filteredTitle: String
    let hint: String
    let clearFilters: () -> Void
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text(isLibraryEmpty ? emptyTitle : filteredTitle)
                .font(.title3.weight(.semibold))
            if isLibraryEmpty {
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                footer()
            } else {
                Button("Clear filters", action: clearFilters)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The search capsule at the head of each Resources list.
struct LibrarySearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 120, maxWidth: 320)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }
}
