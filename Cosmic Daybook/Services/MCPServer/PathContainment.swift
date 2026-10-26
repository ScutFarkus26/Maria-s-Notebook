//
//  PathContainment.swift
//  Cosmic Daybook
//
//  Whether a path Claude names lies inside a folder the guide let it read
//  (plan "Lesson file attachments", Decision 4). Platform-neutral, with the
//  home folder injectable, so the rules are tested on the iOS simulator; only
//  the folder bookmarks and the Settings row are Mac-only (`MCPAttachFolders`).
//

import Darwin
import Foundation

/// The rules a path passes before a lesson-file tool reads it:
/// - `~` is expanded against `home`, the user's **real** home folder (in the
///   sandbox `NSHomeDirectory()` is the app's container);
/// - the file and every root are resolved to their real paths, so `..` and
///   symbolic links can't lead out of a root;
/// - a root contains a path only up to a "/" (`…/YYLI` doesn't contain
///   `…/YYLI2`);
/// - `refused` folders are never read, wherever a root reaches: the folder
///   holding the MCP token and the app's own container. The sandbox would let
///   the app read both, so this check is what keeps them out.
nonisolated struct PathContainment: Sendable {
    /// Where a path landed.
    enum Verdict: Equatable {
        /// Inside `root`; `file` is the file's real location.
        case inside(root: URL, file: URL)
        /// Not inside any root.
        case outside
        /// Inside one of the folders that are never read.
        case refused
        /// Not a full path: it starts with neither "/" nor "~".
        case notAbsolute
    }

    /// The folder `~` stands for.
    let home: URL
    /// Folders never read, even inside a root.
    let refused: [URL]

    /// `refused` defaults to `home/.cosmic-daybook`, the MCP token's folder.
    init(home: URL, refused: [URL]? = nil) {
        self.home = home
        self.refused = refused ?? [home.appendingPathComponent(".cosmic-daybook", isDirectory: true)]
    }

    /// The app's rules: the real home, and the token folder and the app's own
    /// container refused.
    static var live: PathContainment {
        let home = realHome
        var refused = [home.appendingPathComponent(".cosmic-daybook", isDirectory: true)]
        let container = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        if container.standardizedFileURL.path != home.standardizedFileURL.path {
            // Sandboxed, NSHomeDirectory() is …/Containers/<bundle id>/Data.
            refused.append(container.deletingLastPathComponent())
        }
        return PathContainment(home: home, refused: refused)
    }

    /// The user's home folder from the user database, not the sandbox's.
    static var realHome: URL {
        let path = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) }
            ?? NSHomeDirectory()
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    // MARK: - Checking a path

    /// `path` with a leading `~` or `~/` expanded against `home`; nil when the
    /// path isn't a full one. `~user` forms aren't accepted.
    func expand(_ path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" { return home }
        if trimmed.hasPrefix("~/") {
            return home.appendingPathComponent(String(trimmed.dropFirst(2)))
        }
        guard trimmed.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: trimmed)
    }

    /// Where `path` lands among `roots`. A refused folder wins over a root that
    /// holds it. A path that doesn't exist is judged by where it would be, so a
    /// missing file inside a root reads as missing (the caller's check says
    /// so), not as outside.
    func locate(_ path: String, in roots: [URL]) -> Verdict {
        guard let expanded = expand(path) else { return .notAbsolute }
        let target = Self.realPath(of: expanded)
        if refused.contains(where: { Self.contains(Self.realPath(of: $0), target) }) {
            return .refused
        }
        for root in roots {
            // A root that isn't there (an unplugged drive) contains nothing.
            guard let rootPath = Self.existingRealPath(of: root) else { continue }
            if Self.contains(rootPath, target) {
                return .inside(root: root, file: URL(fileURLWithPath: target))
            }
        }
        return .outside
    }

    /// Whether `path` is `folder` or lies inside it. Both are real paths.
    static func contains(_ folder: String, _ path: String) -> Bool {
        if path == folder { return true }
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        return path.hasPrefix(prefix)
    }

    /// The real path of `url` (`realpath(3)`: `..`, `.` and every symbolic link
    /// resolved). For a path that doesn't exist, its folder's real path plus
    /// its name, or failing that the path made standard.
    static func realPath(of url: URL) -> String {
        if let real = existingRealPath(of: url) { return real }
        let parent = url.deletingLastPathComponent()
        if let real = existingRealPath(of: parent) {
            return (real as NSString).appendingPathComponent(url.lastPathComponent)
        }
        return url.standardizedFileURL.path
    }

    /// `realpath(3)` of something that exists; nil when it doesn't.
    static func existingRealPath(of url: URL) -> String? {
        url.withUnsafeFileSystemRepresentation { pointer -> String? in
            guard let pointer, let resolved = Darwin.realpath(pointer, nil) else { return nil }
            defer { free(resolved) }
            return String(validatingCString: resolved)
        }
    }
}
