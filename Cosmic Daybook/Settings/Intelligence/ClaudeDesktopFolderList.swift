//
//  ClaudeDesktopFolderList.swift
//  Cosmic Daybook
//
//  The Claude Desktop card's "Folders Claude can attach files from": the
//  folders `attach_file_to_lesson` may read a file from, with Add Folder…
//  and Remove (plan "Lesson file attachments", Decision 4). Mac only: a
//  folder grant is a security-scoped bookmark, which opens only on this Mac.
//

#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct ClaudeDesktopFolderList: View {
    @State private var folders: [URL] = []
    @State private var isChoosingFolder = false
    @State private var addFailed = false

    private typealias Copy = SettingsCopy.ClaudeDesktopFolders

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text(Copy.title)

            if folders.isEmpty {
                Text(Copy.empty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                    ForEach(folders, id: \.self) { folder in
                        row(for: folder)
                    }
                }
            }

            Button(Copy.add) { isChoosingFolder = true }

            if addFailed {
                Label(Copy.notAdded, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColors.warning)
                    .font(.caption)
            }

            Text(Copy.footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let folder) = result else { return }
            addFailed = !MCPAttachFolders.grant(folder)
            reload()
        }
        .onAppear(perform: reload)
    }

    private func row(for folder: URL) -> some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(folder.lastPathComponent)
                Text(Self.displayPath(of: folder))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: AppTheme.Spacing.small)
            Button(Copy.remove) {
                MCPAttachFolders.revoke(folder)
                reload()
            }
            .help(Copy.removeHelp)
        }
    }

    private func reload() {
        folders = MCPAttachFolders.grantedFolders()
    }

    /// The folder's path with the real home folder shown as "~" (in the
    /// sandbox `abbreviatingWithTildeInPath` would use the app's container).
    static func displayPath(of folder: URL) -> String {
        let path = folder.standardizedFileURL.path
        let home = PathContainment.realHome.standardizedFileURL.path
        guard PathContainment.contains(home, path) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
#endif
