// AlbumLibrary+FolderBookmarks.swift
// The saved album-folder bookmarks: what the list keeps when a folder is added
// or removed, and the folder access the library holds.

import Foundation

extension AlbumLibrary {

    /// The stored folder bookmarks after `chooseFolder` adds one: each folder
    /// once, with the folders they open. `resolve` opens a bookmark, nil when
    /// its folder can't be reached. A folder that can't be reached right now
    /// (an unplugged drive) keeps its bookmark for when it comes back.
    static func dedupedBookmarks(_ list: [Data], resolve: (Data) -> URL?) -> (kept: [Data], folders: [URL]) {
        var folders: [URL] = []
        var seen = Set<String>()
        var kept: [Data] = []
        for data in list {
            guard let folder = resolve(data) else {
                if !kept.contains(data) { kept.append(data) }
                continue
            }
            let path = folder.standardizedFileURL.path
            guard !seen.contains(path) else { continue }
            seen.insert(path)
            kept.append(data)
            folders.append(folder)
        }
        return (kept, folders)
    }

    /// The stored folder bookmarks after `removeFolder` takes out the folder at
    /// `path`. One that can't be reached right now isn't that folder, so it stays.
    static func bookmarks(_ list: [Data], removingFolderAt path: String, resolve: (Data) -> URL?) -> [Data] {
        list.filter { data in
            guard let folder = resolve(data) else { return true }
            return folder.standardizedFileURL.path != path
        }
    }

    // MARK: Folder access

    /// Security-scoped access, as a pair of calls a test can stand in for.
    struct ScopeAccess {
        var start: (URL) -> Bool
        var stop: (URL) -> Void

        static let live = ScopeAccess(
            start: { $0.startAccessingSecurityScopedResource() },
            stop: { $0.stopAccessingSecurityScopedResource() }
        )
    }

    /// A stored folder bookmark's folder, without starting access to it.
    func resolveFolder(_ data: Data) -> URL? {
        try? SecurityScopedBookmark.resolve(data).url
    }

    /// Starts security-scoped access to `folders`, leaving out one whose access
    /// can't start, and stops the access the previous call started. Each chosen
    /// folder is held once however often the bookmarks are resolved again, and
    /// a removed folder is let go. New access starts before the old stops, so a
    /// folder kept across the call is never without it.
    func holdAccess(to folders: [URL]) -> [URL] {
        let opened = folders.filter { scopeAccess.start($0) }
        for folder in accessedFolders { scopeAccess.stop(folder) }
        accessedFolders = opened
        return opened
    }
}
