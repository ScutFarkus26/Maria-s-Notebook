//
//  MCPAttachFolders.swift
//  Cosmic Daybook
//
//  The folders `attach_file_to_lesson` may read a file from: the ones the
//  guide grants in Settings › Claude Desktop, plus her album folders (plan
//  "Lesson file attachments", Decision 4). The app is sandboxed, so a path
//  under ~/Documents can be read only inside a folder the guide chose herself
//  and the app kept a security-scoped bookmark of.
//
//  The grant is kept on this Mac only: a bookmark opens its folder only on the
//  Mac that made it, so the key is left out of iCloud preference sync and out
//  of "Move settings to another device". Backups carry it (merged with the
//  Mac's own list, like the album folders), so a reinstall keeps the grant.
//  Nothing in a granted folder is indexed or read until a tool names a file.
//

import Foundation

enum MCPAttachFolders {
    /// Security-scoped bookmarks (`[Data]`) of the granted folders.
    static let bookmarksKey = UserDefaultsKeys.aiMCPAttachFolderBookmarks

    // MARK: - Reading a file

    /// Says again, just before a file is read, whether it lies inside the
    /// folders, given where it really is then; throws the same plain refusal
    /// when it no longer does.
    typealias Recheck = (URL) throws -> Void

    /// What a tool needs to read a file: the path rules, the folders, and
    /// security-scoped access to them. Tests pass scratch folders and no-op
    /// access.
    struct Access: Sendable {
        var containment: PathContainment
        var roots: @MainActor @Sendable () -> [URL]
        var startAccess: @Sendable (URL) -> Bool
        var stopAccess: @Sendable (URL) -> Void
        /// Runs with the file's real location once the path has passed its
        /// check. Nothing in the app; tests swap the file here, standing in
        /// for another process changing it before it is read.
        var afterCheck: @Sendable (URL) -> Void = { _ in }

        /// The granted folders and the album folders, through their bookmarks.
        static let live = Access(
            containment: .live,
            roots: { MCPAttachFolders.allowedRoots() },
            startAccess: { $0.startAccessingSecurityScopedResource() },
            stopAccess: { $0.stopAccessingSecurityScopedResource() }
        )

        /// Runs `body` with the real location of the file at `path`, while the
        /// folders are open, and closes them afterwards. Throws a plain refusal
        /// when the path isn't a full one or lies outside every folder. The
        /// file can change between this check and the read (a symbolic link
        /// put in its place), so `body` also gets a `Recheck`, to run on the
        /// very file it is about to copy.
        func withReadAccess<T>(to path: String, _ body: (URL, Recheck) async throws -> T) async throws -> T {
            let folders = roots()
            // Access starts before the path is resolved: inside the sandbox
            // even reading where a symbolic link leads needs it.
            let opened = folders.filter { startAccess($0) }
            defer { opened.forEach { stopAccess($0) } }
            let file = try located(path, in: folders)
            afterCheck(file)
            return try await body(file) { candidate in
                _ = try located(candidate.path, in: folders)
            }
        }

        /// Where the file at `path` really is, when that is inside `folders`;
        /// otherwise the plain refusal.
        private func located(_ path: String, in folders: [URL]) throws -> URL {
            switch containment.locate(path, in: folders) {
            case .inside(_, let file):
                return file
            case .notAbsolute:
                throw MCPToolError(
                    "\"\(path)\" isn't a full path. Give the file's whole path, starting with / or ~/."
                )
            case .refused:
                throw MCPToolError("That file belongs to Cosmic Daybook itself, so it can't be attached.")
            case .outside:
                throw MCPToolError(MCPAttachFolders.outsideMessage(hasFolders: !folders.isEmpty))
            }
        }
    }

    /// Why a path outside the folders was refused, naming where to grant one.
    static func outsideMessage(hasFolders: Bool) -> String {
        let lead = hasFolders
            ? "Cosmic Daybook can't read that file: it isn't in a folder the guide has let Claude attach files from."
            : "Cosmic Daybook can't read that file: no folders are set up for Claude to attach files from yet."
        return lead + " Ask the guide to add its folder in Cosmic Daybook's Settings › Claude Desktop › "
            + "\(SettingsCopy.ClaudeDesktopFolders.title) on this Mac, then try again. "
            + "Files in her album folders can be attached too."
    }

    // MARK: - The folders

    /// The granted folders followed by the album folders, each resolved
    /// straight from its bookmark, without starting access. A stale bookmark
    /// is made again and saved in its place; one whose folder can't be
    /// reached is skipped. The album library isn't loaded for this: when the
    /// bridge starts the app with no window, it has no folders open.
    static func allowedRoots(defaults: UserDefaults = .standard) -> [URL] {
        var roots: [URL] = []
        var seen = Set<String>()
        for key in [bookmarksKey, UserDefaultsKeys.albumsFolderBookmarks] {
            for folder in resolveFolders(forKey: key, defaults: defaults) {
                let path = folder.standardizedFileURL.path
                if seen.insert(path).inserted { roots.append(folder) }
            }
        }
        return roots
    }

    /// The folders a bookmark list under `key` opens, remaking stale ones.
    private static func resolveFolders(forKey key: String, defaults: UserDefaults) -> [URL] {
        var list = (defaults.array(forKey: key) as? [Data]) ?? []
        var folders: [URL] = []
        var remade = false
        for (index, data) in list.enumerated() {
            guard let resolved = try? SecurityScopedBookmark.resolve(data) else { continue }
            folders.append(resolved.url)
            guard resolved.isStale else { continue }
            let accessing = resolved.url.startAccessingSecurityScopedResource()
            defer { if accessing { resolved.url.stopAccessingSecurityScopedResource() } }
            if let fresh = try? SecurityScopedBookmark.make(for: resolved.url, unscopedOptions: .minimalBookmark) {
                list[index] = fresh
                remade = true
            }
        }
        if remade { defaults.set(list, forKey: key) }
        return folders
    }

    #if os(macOS)
    // MARK: - Granting (Settings › Claude Desktop)

    /// The granted folders, as Settings lists them.
    static func grantedFolders(defaults: UserDefaults = .standard) -> [URL] {
        resolveFolders(forKey: bookmarksKey, defaults: defaults)
    }

    /// Grants the folder the guide picked (a `fileImporter` URL, so its access
    /// is held only while the bookmark is made). Each folder is kept once.
    /// Returns false when no bookmark could be made.
    @discardableResult
    static func grant(_ folder: URL, defaults: UserDefaults = .standard) -> Bool {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        guard let data = try? SecurityScopedBookmark.make(for: folder) else { return false }
        var list = (defaults.array(forKey: bookmarksKey) as? [Data]) ?? []
        list.append(data)
        let deduped = AlbumLibrary.dedupedBookmarks(list) { try? SecurityScopedBookmark.resolve($0).url }
        defaults.set(deduped.kept, forKey: bookmarksKey)
        return true
    }

    /// Takes a granted folder off the list.
    static func revoke(_ folder: URL, defaults: UserDefaults = .standard) {
        let list = (defaults.array(forKey: bookmarksKey) as? [Data]) ?? []
        let kept = AlbumLibrary.bookmarks(list, removingFolderAt: folder.standardizedFileURL.path) {
            try? SecurityScopedBookmark.resolve($0).url
        }
        defaults.set(kept, forKey: bookmarksKey)
    }
    #endif
}
