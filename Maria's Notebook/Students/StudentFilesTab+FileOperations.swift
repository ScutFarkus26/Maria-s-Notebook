// StudentFilesTab+FileOperations.swift
// File operation methods extracted from StudentFilesTab

import SwiftUI
import UniformTypeIdentifiers
import os
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension StudentFilesTab {
    func openDocumentInDefaultApp(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        #endif
    }

    func handleDrop(_ urls: [URL]) -> Bool {
        guard let url = urls.first else { return false }

        do {
            let gotAccess = url.startAccessingSecurityScopedResource()
            defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            // Passing the original URL allows DocumentImportSheet to extract the correct filename
            selectedImportData = ImportDataWrapper(url: url, data: data)
            return true
        } catch {
            return false
        }
    }

    func deleteDocument(_ document: Document) {
        do {
            try repository.deleteDocument(id: document.id)
        } catch {
            Self.logger.warning("Failed to delete document: \(error)")
        }
    }

    func renameDocument(_ document: Document) {
        documentToRename = document
        renameTitleText = document.title
        showRenameAlert = true
    }

    var renameSheet: some View {
        NavigationStack {
            Form {
                Section("Document Title") {
                    TextField("Title", text: $renameTitleText)
                }
            }
            .navigationTitle("Rename Document")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        documentToRename = nil
                        renameTitleText = ""
                        showRenameAlert = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveRename()
                    }
                    .disabled(renameTitleText.trimmed().isEmpty)
                }
            }
        }
    }

    func saveRename() {
        guard let document = documentToRename else { return }
        let trimmedTitle = renameTitleText.trimmed()
        guard !trimmedTitle.isEmpty else { return }

        repository.updateDocument(id: document.id, title: trimmedTitle)
        _ = repository.save(reason: "Rename document")

        documentToRename = nil
        renameTitleText = ""
        showRenameAlert = false
    }

    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                await loadPDFData(from: url)
            }
        case .failure:
            break
        }
    }

    func loadPDFData(from url: URL) async {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            await MainActor.run {
                selectedImportData = ImportDataWrapper(url: url, data: data)
            }
        } catch {
            // Failed to load PDF data - continue silently
        }
    }

    #if os(macOS)
    func presentMacOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    await loadPDFData(from: url)
                }
            }
        }
    }
    #endif
}
