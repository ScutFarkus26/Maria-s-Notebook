// QuickNoteViewModel+Photo.swift
// Attaching a picked or captured photo to a quick note.

import OSLog
import PhotosUI
import SwiftUI

extension QuickNoteViewModel {
    private static let photoLogger = Logger.notes

    /// Starts loading the photo she picked. Save is off from now until it is
    /// stored (`isLoadingPhoto`), or until `photoLoadLimit` passes; a nil item
    /// (the photo taken off) ends the wait.
    func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else {
            loadingPhotoItem = nil
            return
        }
        loadingPhotoItem = item
        Task {
            await loadPhoto(item) { try await item.loadTransferable(type: Data.self) }
        }
    }

    /// Loads `item`'s bytes with `loadData` and attaches them, keeping Save off
    /// until then while `item` is the latest pick. A photo that hasn't come
    /// after `photoLoadLimit` is given up on, so a stalled iCloud Photos
    /// download no longer holds Save and her typed note (review of the
    /// 2026-10-17 fixes, a2 #5); if it lands later it is no longer the pick,
    /// so its file is deleted.
    func loadPhoto(_ item: PhotosPickerItem, loadData: () async throws -> Data?) async {
        loadingPhotoItem = item
        photoLoadMessage = nil
        let limit = photoLoadLimit
        let giveUp = Task { [weak self] in
            try await Task.sleep(for: limit)
            self?.giveUpOnPhoto(item)
        }
        defer {
            giveUp.cancel()
            if loadingPhotoItem == item { loadingPhotoItem = nil }
        }
        do {
            if let data = try await loadData() {
                await attachPhotoData(data, from: item)
            }
        } catch {
            Self.photoLogger.warning("Failed to load photo: \(error)")
        }
    }

    /// Stops waiting for `item` when it is still the photo being loaded.
    private func giveUpOnPhoto(_ item: PhotosPickerItem) {
        guard loadingPhotoItem == item, selectedPhotoItem == item, !didSave else { return }
        Self.photoLogger.warning("Gave up waiting for a picked photo")
        selectedPhotoItem = nil
        loadingPhotoItem = nil
        photoLoadMessage = Self.photoTooSlowMessage
    }

    static let photoTooSlowMessage = "The photo took too long to arrive, so it wasn't added. "
        + "Try picking it again."

    /// Stores a picked photo off the main thread (ImageIO transcodes it, as in
    /// `PhotoStorageService.savePickedPhoto`) and keeps a preview sized for the
    /// attachment chip instead of the decoded photo.
    func attachPhotoData(_ data: Data, from item: PhotosPickerItem) async {
        let scale = DisplayScale.current
        let result = await PhotoStorageService.savePickedPhoto(
            data, previewSide: NotePhotoPreview.quickNoteSide, scale: scale
        )
        // A newer pick replaced this one while it was being saved, or the note
        // saved (or was discarded) without it: nothing will ever point at this
        // file, so it goes. A late photo used to stay in iCloud for good.
        guard selectedPhotoItem == item, !didSave else {
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
            deleteAttachedPhotoFile()
            self.attachedImage = preview.map { NotePhotoPreview.image($0, scale: scale) }
            self.attachedImagePath = filename
        case .failed(let preview, let error):
            // As before: the attachment still shows, with no file behind it
            // (and not the file of a photo it replaced).
            deleteAttachedPhotoFile()
            self.attachedImagePath = nil
            self.attachedImage = preview.map { NotePhotoPreview.image($0, scale: scale) }
            Self.photoLogger.error("Failed to save image: \(error)")
        }
    }

    /// Takes the photo off the note and deletes its file: nothing else points
    /// at a photo attached to a note that isn't saved yet. Removing it used to
    /// leave the file on disk (and in iCloud) for good.
    func removeAttachedPhoto() {
        deleteAttachedPhotoFile()
        attachedImage = nil
        attachedImagePath = nil
    }

    /// Deletes the file of the photo attached now, which a newer photo is
    /// replacing or she removed. Never after the note is saved: the file is
    /// the note's then.
    private func deleteAttachedPhotoFile() {
        guard !didSave, let filename = attachedImagePath, !filename.isEmpty else { return }
        do {
            try PhotoStorageService.deleteImage(filename: filename)
        } catch {
            Self.photoLogger.error("Failed to delete removed image: \(error)")
        }
    }

    #if !os(macOS)
    /// Saves a camera capture, then swaps the full-size image for a preview.
    /// The shot replaces a library photo still loading: that pick is cleared,
    /// so when it lands it is the one deleted. A camera shot isn't saved to
    /// Photos, and deleting it instead lost it for good (review of the
    /// 2026-10-17 fixes, a2 #2).
    func processImage(_ image: PlatformImage) {
        selectedPhotoItem = nil
        loadingPhotoItem = nil
        photoLoadMessage = nil
        self.attachedImage = image
        do {
            let filename = try PhotoStorageService.saveImage(image)
            deleteAttachedPhotoFile()
            self.attachedImagePath = filename
            showPreview(ofSavedPhoto: filename)
        } catch {
            Self.photoLogger.error("Failed to save image: \(error)")
            deleteAttachedPhotoFile()
            self.attachedImagePath = nil
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
