import SwiftUI
import SwiftData

// MARK: - CSV Import Handlers

extension StudentsView {

    func handleFileImport(_ result: Result<URL, Error>) {
        isParsing = true
        let importResult = StudentsCSVImportHandler.handleFileImport(
            result,
            cancellingTask: parsingTask,
            onHeadersScanned: { headers, mapping, fileURL in
                self.pendingFileURL = fileURL
                self.mappingHeaders = headers
                self.pendingMapping = mapping
                self.showingMappingSheet = true
            },
            onError: { alert in
                self.importAlert = alert
            },
            onFinally: {
                self.isParsing = false
                self.parsingTask = nil
            }
        )
        parsingTask = importResult.task
        if let error = importResult.immediateError {
            importAlert = error
        }
    }

    func handleMappingConfirm(_ mapping: StudentCSVImporter.Mapping) {
        isParsing = true
        parsingTask = StudentsCSVImportHandler.handleMappingConfirm(
            mapping: mapping,
            fileURL: pendingFileURL,
            students: students,
            cancellingTask: parsingTask,
            onParsed: { parsed in
                self.pendingParsedImport = parsed
                self.showingMappingSheet = false
            },
            onError: { alert in
                self.importAlert = alert
                self.showingMappingSheet = false
            },
            onFinally: {
                self.isParsing = false
                self.parsingTask = nil
            }
        )
    }

    func handleImportCommit(_ filtered: StudentCSVImporter.Parsed) {
        importAlert = StudentsCSVImportHandler.handleImportCommit(
            filtered,
            modelContext: modelContext,
            existingStudents: students
        )
        pendingParsedImport = nil
    }
}
