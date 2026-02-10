// Maria's Notebook/Services/CurriculumIntroductionStore.swift
//
// Manages loading, saving, and caching of curriculum introductions.
// Introductions are stored as JSON in the app's Documents directory.
// Also supports bundled default introductions that ship with the app.

import Foundation
import os.log

/// Service for managing curriculum introductions stored as JSON files.
@Observable
@MainActor
final class CurriculumIntroductionStore {
    static let shared = CurriculumIntroductionStore()

    private let logger = Logger.app(category: "CurriculumIntroductionStore")

    /// All loaded introductions (merged from bundle defaults and user customizations)
    private(set) var introductions: [CurriculumIntroduction] = []

    /// Whether the store has completed initial loading
    private(set) var isLoaded: Bool = false

    private let fileName = "curriculum_introductions.json"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - File Paths

    private var userFileURL: URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first 
            ?? FileManager.default.temporaryDirectory
        return documentsURL.appendingPathComponent(fileName)
    }

    private var bundledFileURL: URL? {
        Bundle.main.url(forResource: "curriculum_introductions", withExtension: "json")
    }

    // MARK: - Loading

    /// Loads introductions from disk, merging bundled defaults with user customizations
    func load() async {
        var bundledIntros: [CurriculumIntroduction] = []
        var userIntros: [CurriculumIntroduction] = []

        // Load bundled defaults
        if let bundleURL = bundledFileURL {
            do {
                let data = try Data(contentsOf: bundleURL)
                let library = try decoder.decode(CurriculumIntroductionLibrary.self, from: data)
                bundledIntros = library.introductions
                logger.info("Loaded \(bundledIntros.count) bundled introductions")
            } catch {
                logger.warning("Failed to load bundled introductions: \(error.localizedDescription)")
            }
        }

        // Load user customizations
        if FileManager.default.fileExists(atPath: userFileURL.path) {
            do {
                let data = try Data(contentsOf: userFileURL)
                let library = try decoder.decode(CurriculumIntroductionLibrary.self, from: data)
                userIntros = library.introductions
                logger.info("Loaded \(userIntros.count) user introductions")
            } catch {
                logger.warning("Failed to load user introductions: \(error.localizedDescription)")
            }
        }

        // Merge: user intros override bundled ones (matched by subject+group)
        let merged = mergeIntroductions(bundled: bundledIntros, user: userIntros)

        introductions = merged
        isLoaded = true
    }

    /// Merges bundled and user introductions, with user taking precedence
    private func mergeIntroductions(
        bundled: [CurriculumIntroduction],
        user: [CurriculumIntroduction]
    ) -> [CurriculumIntroduction] {
        var result: [CurriculumIntroduction] = []
        var userKeys = Set<String>()

        // Build set of user-customized keys
        for intro in user {
            let key = makeKey(subject: intro.subject, group: intro.group)
            userKeys.insert(key)
            result.append(intro)
        }

        // Add bundled intros that don't have user overrides
        for intro in bundled {
            let key = makeKey(subject: intro.subject, group: intro.group)
            if !userKeys.contains(key) {
                result.append(intro)
            }
        }

        return result
    }

    private func makeKey(subject: String, group: String?) -> String {
        let normalizedSubject = subject.trimmed().lowercased()
        let normalizedGroup = (group ?? "").trimmed().lowercased()
        return "\(normalizedSubject)::\(normalizedGroup)"
    }

    // MARK: - Querying

    /// Returns the introduction for a specific subject and group
    func introduction(for subject: String, group: String?) -> CurriculumIntroduction? {
        let key = makeKey(subject: subject, group: group)
        return introductions.first { makeKey(subject: $0.subject, group: $0.group) == key }
    }

    /// Returns the album-level introduction for a subject
    func albumIntroduction(for subject: String) -> CurriculumIntroduction? {
        introduction(for: subject, group: nil)
    }

    /// Returns the group-level introduction
    func groupIntroduction(for subject: String, group: String) -> CurriculumIntroduction? {
        introduction(for: subject, group: group)
    }

    /// Returns true if an introduction exists for the given subject and group
    func hasIntroduction(for subject: String, group: String?) -> Bool {
        introduction(for: subject, group: group) != nil
    }

    /// Returns all introductions for a given subject (album + all groups)
    func introductions(for subject: String) -> [CurriculumIntroduction] {
        let normalizedSubject = subject.trimmed().lowercased()
        return introductions.filter {
            $0.subject.trimmed().lowercased() == normalizedSubject
        }
    }

    // MARK: - Saving

    /// Saves or updates an introduction
    func save(_ introduction: CurriculumIntroduction) async throws {
        var updated = introduction
        updated.modifiedAt = Date()

        // Remove existing if present
        let key = makeKey(subject: updated.subject, group: updated.group)
        introductions.removeAll { makeKey(subject: $0.subject, group: $0.group) == key }

        // Add the new/updated one
        introductions.append(updated)

        // Persist to user file
        try await persistUserIntroductions()
    }

    /// Deletes an introduction (only removes user customization; bundled will reappear on reload)
    func delete(_ introduction: CurriculumIntroduction) async throws {
        let key = makeKey(subject: introduction.subject, group: introduction.group)
        introductions.removeAll { makeKey(subject: $0.subject, group: $0.group) == key }

        try await persistUserIntroductions()
    }

    /// Persists all user-modified introductions to disk
    private func persistUserIntroductions() async throws {
        // Only persist introductions that differ from bundled defaults
        // For simplicity, we persist all current intros as user intros
        // A more sophisticated approach would track which are user-modified
        let library = CurriculumIntroductionLibrary(introductions: introductions, version: 1)
        let data = try encoder.encode(library)
        try data.write(to: userFileURL, options: .atomic)
        logger.info("Saved \(self.introductions.count) introductions to disk")
    }

    // MARK: - Import/Export

    /// Imports introductions from a JSON file URL
    func importIntroductions(from url: URL) async throws -> Int {
        let data = try Data(contentsOf: url)
        let library = try decoder.decode(CurriculumIntroductionLibrary.self, from: data)

        var importCount = 0
        for intro in library.introductions {
            let key = makeKey(subject: intro.subject, group: intro.group)
            // Only add if not already present
            if !introductions.contains(where: { makeKey(subject: $0.subject, group: $0.group) == key }) {
                introductions.append(intro)
                importCount += 1
            }
        }

        if importCount > 0 {
            try await persistUserIntroductions()
        }

        return importCount
    }

    /// Exports all introductions to a JSON file and returns the URL
    func exportIntroductions() async throws -> URL {
        let library = CurriculumIntroductionLibrary(introductions: introductions, version: 1)
        let data = try encoder.encode(library)

        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("curriculum_introductions_export")
            .appendingPathExtension("json")

        try data.write(to: exportURL, options: .atomic)
        return exportURL
    }
}
