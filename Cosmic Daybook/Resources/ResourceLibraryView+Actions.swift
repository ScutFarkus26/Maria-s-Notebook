// ResourceLibraryView+Actions.swift
// Data mutation actions, selection management, bulk operations, and drag-and-drop import.

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

extension ResourceLibraryView {

    // MARK: - Individual Actions

    func deleteResource(_ resource: CDResource) {
        viewContext.delete(resource)
        dependencies.saveCoordinator.save(viewContext, reason: "Delete resource")
    }

    func toggleFavorite(_ resource: CDResource) {
        resource.isFavorite.toggle()
        resource.modifiedAt = Date()
        dependencies.saveCoordinator.save(viewContext, reason: "Toggle favorite")
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
        dependencies.saveCoordinator.save(viewContext, reason: "Toggle favorites")
    }

    func bulkSetCategory(_ category: ResourceCategory) {
        for resource in selectedResources {
            resource.category = category
            resource.modifiedAt = Date()
        }
        dependencies.saveCoordinator.save(viewContext, reason: "Update resource category")
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
        dependencies.saveCoordinator.save(viewContext, reason: "Add resource tags")
    }

    func bulkDelete() {
        for resource in selectedResources {
            viewContext.delete(resource)
        }
        dependencies.saveCoordinator.save(viewContext, reason: "Delete resources")
        exitSelectMode()
    }

    // MARK: - Drag and Drop

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var didImport = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, error in
                guard let url else {
                    if let error {
                        Logger.resources.warning("Drop failed: \(error.localizedDescription, privacy: .public)")
                    }
                    Task { @MainActor in
                        dependencies.toastService.showError("Couldn't add the PDF you dropped. Try again.")
                    }
                    return
                }

                // Copy the file before the callback closes it, keeping its own
                // name (in a folder of its own) so the resource is titled after it.
                let tempFolder = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                let tempURL = tempFolder.appendingPathComponent(url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: tempURL)
                } catch {
                    Logger.resources.warning(
                        "Couldn't copy a dropped PDF: \(error.localizedDescription, privacy: .public)"
                    )
                    Task { @MainActor in
                        dependencies.toastService.showError(AppErrorMessages.importMessage(for: error, fileType: "PDF"))
                    }
                    return
                }

                Task { @MainActor in
                    importDroppedPDF(from: tempURL)
                }
            }
            didImport = true
        }
        return didImport
    }

    func importDroppedPDF(from tempURL: URL) {
        let stem = tempURL.deletingPathExtension().lastPathComponent.trimmed()
        let title = stem.isEmpty ? "Untitled Resource" : stem

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
            dependencies.saveCoordinator.save(viewContext, reason: "Import dropped PDF")
        } catch {
            Logger.resources.warning("Dropped PDF import failed: \(error.localizedDescription, privacy: .public)")
            dependencies.toastService.showError(AppErrorMessages.importMessage(for: error, fileType: "PDF"))
        }

        // Clean up the temp copy and its folder
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }
}
