// AlbumsLibraryView+NewerCopy.swift
// "A newer copy of Biology is in Albums 2026": the row above the album grid,
// and the question Use Newer Copy asks before it changes the album on every
// device.

import SwiftUI

/// "A newer copy of Biology is in Albums 2026", with Use Newer Copy: the
/// original of an album kept in iCloud was edited after it was kept, and the
/// shelf's copy is the one every device reads.
struct NewerCopyRow: View {
    @Environment(AlbumLibrary.self) private var library
    let album: Album
    @State private var confirming = false
    @State private var confirmation = ""

    var body: some View {
        HStack(spacing: 10) {
            Label {
                Text("A newer copy of \(album.title) is in \(folderName).")
            } icon: {
                Image(systemName: "doc.badge.clock")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if library.albumsBeingKept.contains(album.id) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Copying to iCloud")
            } else {
                Button("Use Newer Copy…") {
                    confirmation = NewerCopyWording.confirmation(for: album, in: library)
                    confirming = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .useNewerCopyConfirmation(album, isPresented: $confirming, message: confirmation)
    }

    private var folderName: String {
        library.newerCopy(for: album)?.deletingLastPathComponent().lastPathComponent ?? "another folder"
    }
}

/// What Use Newer Copy says it will do: which copy replaces which, with the
/// dates each was changed (the newer one by date may not be the one she
/// wants), and where the old one goes.
enum NewerCopyWording {
    static func confirmation(for album: Album, in library: AlbumLibrary) -> String {
        let newer = library.newerCopy(for: album)
        let folder = newer?.deletingLastPathComponent().lastPathComponent ?? "another folder"
        var text = "The copy in \(folder) will replace the one in iCloud on every device."
        if let newer,
           let changed = AlbumICloudShelf.modificationDate(of: newer),
           let keptChanged = AlbumICloudShelf.modificationDate(of: album.url) {
            text += " It was changed \(changed.formatted(date: .abbreviated, time: .shortened)); "
                + "the one in iCloud, \(keptChanged.formatted(date: .abbreviated, time: .shortened))."
        }
        return text + " The one in iCloud now goes to \(AlbumICloudShelf.trashName). "
            + "Your bookmarks and notes are kept."
    }
}

extension View {
    /// Asks before Use Newer Copy replaces `album` on every device.
    func useNewerCopyConfirmation(_ album: Album, isPresented: Binding<Bool>, message: String) -> some View {
        modifier(UseNewerCopyConfirmation(album: album, isPresented: isPresented, message: message))
    }
}

private struct UseNewerCopyConfirmation: ViewModifier {
    @Environment(AlbumLibrary.self) private var library
    let album: Album
    @Binding var isPresented: Bool
    let message: String

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Use the newer copy of \(album.title)?",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Use Newer Copy") {
                Task { await library.useNewerCopy(album) }
            }
        } message: {
            Text(message)
        }
    }
}
