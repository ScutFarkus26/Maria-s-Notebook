// ResourceLibraryView+Actions.swift
// Data mutation actions, selection management, bulk operations, and drag-and-drop import.

import SwiftUI
import CoreData
import UniformTypeIdentifiers

extension ResourceLibraryView {

    // MARK: - Individual Actions

    func deleteResource(_ resource: CDResource) {
        viewContext.delete(resource)
        viewContext.safeSave()
    }

    func toggleFavorite(_ resource: CDResource) {
        resource.isFavorite.toggle()
        resource.modifiedAt = Date()
        viewContext.safeSave()
    }

    // MARK: - Selection

    func toggleSelection(_ resource: CDResource) {
        guard let resourceID = resource.id else { return }
        if selectedResourceIDs.contains(resourceID) {
            selectedResourceIDs.remove(resourceID)
        } else {
            selectedResourceIDs.insert(resourceID)
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
        viewContext.safeSave()
    }

    func bulkSetCategory(_ category: ResourceCategory) {
        for resource in selectedResources {
            resource.category = category
            resource.modifiedAt = Date()
        }
        viewContext.safeSave()
    }

    func bulkAddTags(_ tags: [String]) {
        for resource in selectedResources {
            for tag in tags {
                let tagName = TagHelper.tagName(tag).lowercased()
                if !resource.tagsArray.contains(where: { TagHelper.tagName($0).lowercased() == tagName }) {
                    resource.tagsArray.append(tag)
                }
            }
            resource.modifiedAt = Date()
        }
        viewContext.safeSave()
    }

    func bulkDelete() {
        for resource in selectedResources {
            viewContext.delete(resource)
        }
        viewContext.safeSave()
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
        let title = stem.isEmpty ? "Imported CDResource" : stem

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

            let resource = CDResource(context: viewContext)
            resource.title = title
            resource.category = .other
            resource.fileBookmark = bookmark
            resource.fileRelativePath = relativePath
            resource.fileSizeBytes = fileSize
            resource.thumbnailData = thumbnail
            viewContext.safeSave()
        } catch {
            // Silently fail — resource wasn't imported
        }

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)
    }
}
