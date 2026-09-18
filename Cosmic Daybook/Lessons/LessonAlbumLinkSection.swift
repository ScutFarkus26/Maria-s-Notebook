// LessonAlbumLinkSection.swift
// The lesson side of the lesson ↔ album link: shows which album page this
// lesson is written up on, jumps to it, and offers to find a match when the
// lesson isn't linked yet.
//
// Deliberately quiet when the guide has no albums set up — this is an
// optional convenience, not a step the lesson library depends on.

import CoreData
import SwiftUI

struct LessonAlbumLinkSection: View {
    @Environment(AlbumLibrary.self) private var library
    @Environment(\.appRouter) private var appRouter
    @Environment(\.managedObjectContext) private var context

    let lesson: CDLesson

    @State private var showMatchSheet = false

    private var link: AlbumLink? { lesson.albumLink }

    /// The album a link points at, if the library happens to be loaded.
    /// It usually isn't: opening every album PDF is deliberately deferred
    /// until the guide visits the Albums section, so this row is built to
    /// read correctly from the stored link alone.
    private var linkedAlbum: Album? {
        link.flatMap { library.album(id: $0.albumID) }
    }

    /// Display name for the linked album, without needing it loaded.
    private var linkedAlbumTitle: String? {
        guard let link else { return nil }
        if let album = linkedAlbum { return album.title }
        return Album.cleanTitle(from: URL(fileURLWithPath: link.albumID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
            HStack(spacing: AppTheme.Spacing.small + 2) {
                Image(systemName: "books.vertical")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Album")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                menu
            }
            content
        }
        .padding(.top, AppTheme.Spacing.verySmall)
        .sheet(isPresented: $showMatchSheet) {
            LessonAlbumMatchSheet(lessons: [lesson])
        }
    }

    @ViewBuilder
    private var content: some View {
        if let link, let albumTitle = linkedAlbumTitle {
            Button {
                appRouter.navigateToAlbumPage(albumID: link.albumID, pageIndex: link.pageIndex)
            } label: {
                HStack(spacing: AppTheme.Spacing.small) {
                    // Only rendered when the library is already open; the row
                    // reads fine without it.
                    if linkedAlbum != nil {
                        AlbumPageThumbnail(albumID: link.albumID,
                                           pageIndex: link.pageIndex, width: 38)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(link.lessonTitle ?? albumTitle)
                            .font(AppTheme.ScaledFont.body)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 5) {
                            Text("\(albumTitle) · p. \(link.pageIndex + 1)")
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)
                            if lesson.albumLinkConfidence > 0,
                               lesson.albumLinkConfidence < LessonAlbumMatcher.autoLinkThreshold {
                                Text("suggested")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open this lesson in its album")
        } else if library.state == .needsFolder {
            Text("No teaching albums set up yet.")
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.tertiary)
        } else {
            // Opens the match sheet, which indexes the albums itself.
            Button("Find in Albums…") { showMatchSheet = true }
                .font(AppTheme.ScaledFont.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
        }
    }

    @ViewBuilder
    private var menu: some View {
        if link != nil {
            Menu {
                Button("Find a Different Page…") { showMatchSheet = true }
                Button("Remove Link", role: .destructive) {
                    LessonAlbumMatcher.unlink(lesson, in: context)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}
