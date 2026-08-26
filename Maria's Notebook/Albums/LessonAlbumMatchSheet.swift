// LessonAlbumMatchSheet.swift
// The review step for lesson ↔ album linking. Nothing is written until the
// guide accepts it: album outlines repeat lesson titles across levels, so
// bulk-applying every match would quietly point a lower-elementary lesson at
// an upper-elementary write-up. Confident matches come pre-selected;
// everything else starts off.

import CoreData
import PDFKit
import SwiftUI

struct LessonAlbumMatchSheet: View {
    @Environment(AlbumLibrary.self) private var library
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Lessons to consider. Pass one to review a single lesson's options.
    let lessons: [CDLesson]

    @State private var candidates: [LessonAlbumMatcher.Candidate] = []
    @State private var accepted: Set<String> = []
    @State private var isMatching = true

    /// Candidates for one album, in page order.
    private struct AlbumGroup: Identifiable {
        var id: String { albumTitle }
        let albumTitle: String
        let subject: AlbumSubject
        let items: [LessonAlbumMatcher.Candidate]
    }

    private var grouped: [AlbumGroup] {
        Dictionary(grouping: candidates, by: \.albumID)
            .compactMap { _, items -> AlbumGroup? in
                guard let first = items.first else { return nil }
                return AlbumGroup(albumTitle: first.albumTitle, subject: first.subject,
                                  items: items.sorted { $0.pageIndex < $1.pageIndex })
            }
            .sorted { $0.albumTitle.localizedStandardCompare($1.albumTitle) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Match Lessons to Albums")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Link \(accepted.count)") { applyAccepted() }
                            .disabled(accepted.isEmpty)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 460)
        #endif
        .task { await runMatch() }
    }

    @ViewBuilder
    private var content: some View {
        if isMatching {
            ContentUnavailableView {
                Label("Reading the Albums…", systemImage: "sparkles")
            } description: {
                Text("Comparing \(lessons.count) lesson\(lessons.count == 1 ? "" : "s") "
                     + "against every album outline.")
            }
        } else if candidates.isEmpty {
            ContentUnavailableView {
                Label("No Matches Found", systemImage: "questionmark.folder")
            } description: {
                Text("Nothing in the albums looked close enough to these lessons. "
                     + "You can still link a lesson by hand from its detail view.")
            }
        } else {
            List {
                Section { summaryRow }
                ForEach(grouped) { group in
                    Section {
                        ForEach(group.items) { candidate in
                            row(candidate)
                        }
                    } header: {
                        Label(group.albumTitle, systemImage: group.subject.symbol)
                            .foregroundStyle(group.subject.color)
                    }
                }
            }
        }
    }

    private var summaryRow: some View {
        let confident = candidates.filter(\.isConfident)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(candidates.count) suggested link\(candidates.count == 1 ? "" : "s")")
                    .font(.callout.weight(.medium))
                Text("\(confident.count) confident · \(candidates.count - confident.count) worth a look")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(accepted.count == candidates.count ? "Select None" : "Select All") {
                accepted = accepted.count == candidates.count ? [] : Set(candidates.map(\.id))
            }
            .buttonStyle(.bordered)
        }
    }

    private func row(_ candidate: LessonAlbumMatcher.Candidate) -> some View {
        Toggle(isOn: binding(for: candidate)) {
            HStack(alignment: .top, spacing: 12) {
                AlbumPageThumbnail(albumID: candidate.albumID, pageIndex: candidate.pageIndex)
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.lessonName)
                        .font(.callout.weight(.medium))
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(candidate.outlineTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Text("p. \(candidate.pageIndex + 1)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        confidencePill(candidate)
                        if !candidate.lessonArea.isEmpty {
                            Text(candidate.lessonArea)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .albumMatchToggleStyle()
    }

    private func confidencePill(_ candidate: LessonAlbumMatcher.Candidate) -> some View {
        Text(candidate.isConfident ? "Confident" : "\(Int(candidate.score * 100))% match")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(candidate.isConfident ? Color.green.opacity(0.18) : Color.orange.opacity(0.18),
                        in: Capsule())
            .foregroundStyle(candidate.isConfident ? .green : .orange)
    }

    private func binding(for candidate: LessonAlbumMatcher.Candidate) -> Binding<Bool> {
        Binding(
            get: { accepted.contains(candidate.id) },
            set: { isOn in
                if isOn { accepted.insert(candidate.id) } else { accepted.remove(candidate.id) }
            })
    }

    // MARK: Actions

    private func runMatch() async {
        isMatching = true
        await library.ensureIndexed()
        let found = await LessonAlbumMatcher.candidates(for: lessons, library: library)
        candidates = found
        // Confident matches start selected; the rest are opt-in.
        accepted = Set(found.filter(\.isConfident).map(\.id))
        isMatching = false
    }

    private func applyAccepted() {
        let picked = candidates.filter { accepted.contains($0.id) }
        LessonAlbumMatcher.apply(picked, in: context)
        dismiss()
    }
}

// MARK: - Page thumbnail

/// A small render of one album page, so the guide can see what they're
/// linking to without leaving the sheet.
struct AlbumPageThumbnail: View {
    @Environment(AlbumLibrary.self) private var library
    let albumID: String
    let pageIndex: Int
    var width: CGFloat = 46

    @State private var image: PlatformImage?

    var body: some View {
        Group {
            if let image {
                #if os(macOS)
                Image(nsImage: image).resizable()
                #else
                Image(uiImage: image).resizable()
                #endif
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))
        .accessibilityHidden(true)
        .task(id: "\(albumID)|\(pageIndex)") {
            guard image == nil,
                  let page = library.album(id: albumID)?.document.page(at: pageIndex) else { return }
            let size = CGSize(width: width * 3, height: width * 4)
            image = page.thumbnail(of: size, for: .mediaBox)
        }
    }
}

// MARK: - Platform toggle style

private extension View {
    /// Checkboxes read correctly in a review list on the Mac; iOS has no
    /// checkbox style, so rows there keep the default switch.
    @ViewBuilder
    func albumMatchToggleStyle() -> some View {
        #if os(macOS)
        toggleStyle(.checkbox)
        #else
        self
        #endif
    }
}
