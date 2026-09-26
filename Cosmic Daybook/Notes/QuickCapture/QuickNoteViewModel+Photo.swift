// QuickNoteViewModel+Photo.swift
// Attaching a picked or captured photo to a quick note.

import OSLog
import PhotosUI
import SwiftUI

extension QuickNoteViewModel {
    private static let photoLogger = Logger.notes

    func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    await attachPhotoData(data, from: item)
                }
            } catch {
                Self.photoLogger.warning("Failed to load photo: \(error)")
            }
        }
    }

    /// Stores a picked photo off the main thread (ImageIO transcodes it, as in
    /// `PhotoStorageService.savePickedPhoto`) and keeps a preview sized for the
    /// attachment chip instead of the decoded photo.
    private func attachPhotoData(_ data: Data, from item: PhotosPickerItem) async {
        let scale = DisplayScale.current
        let result = await PhotoStorageService.savePickedPhoto(
            data, previewSide: NotePhotoPreview.quickNoteSide, scale: scale
        )
        // A newer pick replaced this one while it was being saved.
        guard selectedPhotoItem == item else {
            if case .saved(let filename, _) = result {
                do {
                    try PhotoStorageService.deleteImage(filename: filename)
                } catch {
                    Self.photoLogger.error("Failed to delete superseded image: \(error)")
                }
            }
            return
        }
        switch result {
        case .notAnImage:
            return
        case .saved(let filename, let preview):
            self.attachedImage = preview.map { NotePhotoPreview.image($0, scale: scale) }
            self.attachedImagePath = filename
        case .failed(let preview, let error):
            // As before: the attachment still shows, with no file behind it.
            self.attachedImage = preview.map { NotePhotoPreview.image($0, scale: scale) }
            Self.photoLogger.error("Failed to save image: \(error)")
        }
    }

    #if !os(macOS)
    /// Saves a camera capture, then swaps the full-size image for a preview.
    func processImage(_ image: PlatformImage) {
        self.attachedImage = image
        do {
            let filename = try PhotoStorageService.saveImage(image)
            self.attachedImagePath = filename
            showPreview(ofSavedPhoto: filename)
        } catch {
            Self.photoLogger.error("Failed to save image: \(error)")
        }
    }

    /// Replaces the full-size capture with a preview sized for the attachment chip,
    /// read from the saved file off the main thread.
    private func showPreview(ofSavedPhoto filename: String) {
        let scale = DisplayScale.current
        Task { [weak self] in
            let preview = await PhotoStorageService.preview(
                ofSavedPhoto: filename, side: NotePhotoPreview.quickNoteSide, scale: scale
            )
            // Only while that photo is still the one attached
            guard let self, let preview, self.attachedImagePath == filename else { return }
            self.attachedImage = NotePhotoPreview.image(preview, scale: scale)
        }
    }
    #endif
}
