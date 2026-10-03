// RelatedLessonsPanel.swift
// Related lessons

import SwiftUI

struct RelatedLessonsPanel: View {
    @Environment(AlbumLibrary.self) private var library
    let album: Album
    let currentPage: Int
    let onSelect: ((albumID: String, pageIndex: Int)) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Related Lessons", systemImage: "arrow.triangle.branch")
                .font(.headline)
            switch library.semantic.status {
            case .ready:
                let matches = relatedMatches
                if matches.isEmpty {
                    Text("No related lessons found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(matches) { match in
                        if let target = library.album(id: match.albumID),
                           target.lessons.indices.contains(match.lessonIndex) {
                            let lesson = target.lessons[match.lessonIndex]
                            Button {
                                onSelect((match.albumID, lesson.pageIndex))
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: target.subject.symbol)
                                        .foregroundStyle(target.subject.color)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(lesson.title)
                                            .font(.callout.weight(.medium))
                                            .multilineTextAlignment(.leading)
                                        Text("\(target.title) · p. \(lesson.pageIndex + 1)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            case .building, .idle:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Preparing the lesson map…")
                        .foregroundStyle(.secondary)
                }
            case .unavailable:
                Text("Related lessons aren't available on this device.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
    }

    private var relatedMatches: [AlbumSemanticIndex.Match] {
        guard let lesson = album.lesson(forPage: currentPage),
              let index = album.lessons.lastIndex(where: {
                  $0.pageIndex == lesson.pageIndex && $0.title == lesson.title
              }) else { return [] }
        return library.semantic.related(albumID: album.id, lessonIndex: index, limit: 5)
    }
}
