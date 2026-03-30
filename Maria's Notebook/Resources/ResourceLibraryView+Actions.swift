// ResourceLibraryView+Actions.swift
// Data mutation actions, selection management, bulk operations, and drag-and-drop import.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CoreData

extension ResourceLibraryView {

    // MARK: - Individual Actions

    func deleteResource(_ resource: Resource) {
        modelContext.delete(resource)
        modelContext.safeSave()
    }

    func toggleFavorite(_ resource: Resource) {
        resource.isFavorite.toggle()
        resource.modifiedAt = Date()
        modelContext.safeSave()
    }

    // MARK: - Selection

    func toggleSelection(_ resource: Resource) {
        if selectedResourceIDs.contains(resource.id) {
            selectedResourceIDs.remove(resource.id)
        } else {
            selectedResourceIDs.insert(resource.id)
        }
    }

    func exitSelectMode() {
        isSelectMode = false
        selectedResourceIDs.removeAll()
    }

    // MARK: - Bulk Actions

    func bulkToggleFavorite() {
        let resources = selectedResources
        let allFavorited = resources.allSatisfy { $0.isFavorite }
        for resource in resources {
            resource.isFavorite = !allFavorited
            resource.modifiedAt = Date()
        }
        modelContext.safeSave()
    }

    func bulkSetCategory(_ category: ResourceCategory) {
        for resource in selectedResources {
            resource.category = category
            resource.modifiedAt = Date()
        }
        modelContext.safeSave()
    }

    func bulkAddTags(_ tags: [String]) {
        for resource in selectedResources {
            for tag in tags {
                let tagName = TagHelper.tagName(tag).lowercased()
                if !resource.tags.contains(where: { TagHelper.tagName($0).lowercased() == tagName }) {
                    resource.tags.append(tag)
                }
            }
            resource.modifiedAt = Date()
        }
        modelContext.safeSave()
    }

    func bulkDelete() {
        for resource in selectedResources {
            modelContext.delete(resource)
        }
        modelContext.safeSave()
        exitSelectMode()
    }

    // MARK: - Drag and Drop

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var didImport = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, _ in
                guard let url else { return }

                // Copy file to a temp location before the callback closes it
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("pdf")
                try? FileManager.default.copyItem(at: url, to: tempURL)

                Task { @MainActor in
                    importDroppedPDF(from: tempURL)
                }
            }
            didImport = true
        }
        return didImport
    }

    @MainActor
    func importDroppedPDF(from tempURL: URL) {
        let stem = tempURL.deletingPathExtension().lastPathComponent
        let title = stem.isEmpty ? "Imported Resource" : stem

        do {
            let resourceID = UUID()
            let (destURL, relativePath) = try ResourceFileStorage.importFile(
                from: tempURL,
                resourceID: resourceID,
                title: title,
                category: .other
            )
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: destURL.path)
            let fileSize = (fileAttributes[.size] as? Int64) ?? 0
            let bookmark = try ResourceFileStorage.makeBookmark(for: destURL)
            let thumbnail = ResourceThumbnailGenerator.generateThumbnail(from: destURL)

            let resource = Resource(
                title: title,
                category: .other,
                fileBookmark: bookmark,
                fileRelativePath: relativePath,
                fileSizeBytes: fileSize,
                thumbnailData: thumbnail
            )
            modelContext.insert(resource)
            modelContext.safeSave()
        } catch {
            // Silently fail — resource wasn't imported
        }

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)
    }
}
