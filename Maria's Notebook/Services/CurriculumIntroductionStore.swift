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

        // Merge: user intros override bundled ones (matched by area+sequence)
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
            let key = makeKey(area: intro.area, sequence: intro.sequence)
            userKeys.insert(key)
            result.append(intro)
        }

        // Add bundled intros that don't have user overrides
        for intro in bundled {
            let key = makeKey(area: intro.area, sequence: intro.sequence)
            if !userKeys.contains(key) {
                result.append(intro)
            }
        }

        return result
    }

    private func makeKey(area: String, sequence: String?) -> String {
        let normalizedArea = area.trimmed().lowercased()
        let normalizedSequence = (sequence ?? "").trimmed().lowercased()
        return "\(normalizedArea)::\(normalizedSequence)"
    }

    // MARK: - Querying

    /// Returns the introduction for a specific area and sequence
    func introduction(for area: String, sequence: String?) -> CurriculumIntroduction? {
        let key = makeKey(area: area, sequence: sequence)
        return introductions.first { makeKey(area: $0.area, sequence: $0.sequence) == key }
    }

    /// Returns the album-level introduction for a area
    func albumIntroduction(for area: String) -> CurriculumIntroduction? {
        introduction(for: area, sequence: nil)
    }

    /// Returns the sequence-level introduction
    func groupIntroduction(for area: String, sequence: String) -> CurriculumIntroduction? {
        introduction(for: area, sequence: sequence)
    }

    /// Returns true if an introduction exists for the given area and sequence
    func hasIntroduction(for area: String, sequence: String?) -> Bool {
        introduction(for: area, sequence: sequence) != nil
    }

    /// Returns all introductions for a given area (album + all groups)
    func introductions(for area: String) -> [CurriculumIntroduction] {
        let normalizedArea = area.trimmed().lowercased()
        return introductions.filter {
            $0.area.trimmed().lowercased() == normalizedArea
        }
    }

    // MARK: - Saving

    /// Saves or updates an introduction
    func save(_ introduction: CurriculumIntroduction) async throws {
        var updated = introduction
        updated.modifiedAt = Date()

        // Remove existing if present
        let key = makeKey(area: updated.area, sequence: updated.sequence)
        introductions.removeAll { makeKey(area: $0.area, sequence: $0.sequence) == key }

        // Add the new/updated one
        introductions.append(updated)

        // Persist to user file
        try await persistUserIntroductions()
    }

    /// Deletes an introduction (only removes user customization; bundled will reappear on reload)
    func delete(_ introduction: CurriculumIntroduction) async throws {
        let key = makeKey(area: introduction.area, sequence: introduction.sequence)
        introductions.removeAll { makeKey(area: $0.area, sequence: $0.sequence) == key }

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
            let key = makeKey(area: intro.area, sequence: intro.sequence)
            // Only add if not already present
            if !introductions.contains(where: { makeKey(area: $0.area, sequence: $0.sequence) == key }) {
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
