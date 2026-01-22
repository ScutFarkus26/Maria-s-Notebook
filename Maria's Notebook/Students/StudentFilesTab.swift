import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PDFKit
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum DocumentSortOption {
    case dateDesc
    case dateAsc
    case title
}

struct StudentFilesTab: View {
    let student: Student
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    private var repository: DocumentRepository {
        DocumentRepository(context: modelContext, saveCoordinator: saveCoordinator)
    }

    @State private var showFileImporter = false
    @State private var selectedImportData: ImportDataWrapper? = nil
    @State private var documentToRename: Document? = nil
    @State private var showRenameAlert = false
    @State private var renameTitleText = ""
    @State private var previewURL: URL? = nil
    @State private var sortOption: DocumentSortOption = .dateDesc
    @State private var filterCategory: String? = nil
    
    private struct ImportDataWrapper: Identifiable {
        let id = UUID()
        let url: URL
        let data: Data
    }
    
    private var allDocuments: [Document] {
        student.documents ?? []
    }
    
    private var documents: [Document] {
        var filtered = allDocuments
        
        // Filter by category if set
        if let category = filterCategory {
            filtered = filtered.filter { $0.category == category }
        }
        
        // Sort based on option
        switch sortOption {
        case .dateDesc:
            filtered.sort { $0.uploadDate > $1.uploadDate }
        case .dateAsc:
            filtered.sort { $0.uploadDate < $1.uploadDate }
        case .title:
            filtered.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        
        return filtered
    }
    
    private var uniqueCategories: [String] {
        let categories = Set(allDocuments.map { $0.category })
        return Array(categories).sorted()
    }
    
    private let columns = [
        GridItem(.adaptive(minimum: 200), spacing: 16)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("Files")
                            .font(.headline)
                        Spacer()
                        
                        Menu {
                            Section("Filter by") {
                                Button {
                                    filterCategory = nil
                                } label: {
                                    Label("All", systemImage: "folder")
                                    if filterCategory == nil {
                                        Image(systemName: "checkmark")
                                    }
                                }
                                
                                ForEach(uniqueCategories, id: \.self) { category in
                                    Button {
                                        filterCategory = category
                                    } label: {
                                        Text(category)
                                        if filterCategory == category {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                            
                            Section("Sort by") {
                                Button {
                                    sortOption = .dateDesc
                                } label: {
                                    Label("Date (Newest)", systemImage: "calendar")
                                    if sortOption == .dateDesc {
                                        Image(systemName: "checkmark")
                                    }
                                }
                                
                                Button {
                                    sortOption = .dateAsc
                                } label: {
                                    Label("Date (Oldest)", systemImage: "calendar")
                                    if sortOption == .dateAsc {
                                        Image(systemName: "checkmark")
                                    }
                                }
                                
                                Button {
                                    sortOption = .title
                                } label: {
                                    Label("Title", systemImage: "textformat")
                                    if sortOption == .title {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        } label: {
                            Label("Filter & Sort", systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            #if os(macOS)
                            presentMacOpenPanel()
                            #else
                            showFileImporter = true
                            #endif
                        } label: {
                            Label("Add File", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    if allDocuments.isEmpty {
                        ContentUnavailableView(
                            "No files yet",
                            systemImage: "folder",
                            description: Text("Add a file to get started")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else if documents.isEmpty {
                        ContentUnavailableView(
                            "No matching files",
                            systemImage: "magnifyingglass",
                            description: Text("Try adjusting your filter or sort options")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(documents) { document in
                                DocumentCard(
                                    document: document,
                                    onOpen: { url in
                                        previewURL = url
                                    },
                                    onDelete: {
                                        deleteDocument(document)
                                    },
                                    onRename: {
                                        renameDocument(document)
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
            }
            .dropDestination(for: URL.self) { items, location in
                return handleDrop(items)
            }
        }
        #if os(iOS)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        #endif
        .sheet(item: $selectedImportData) { wrapper in
            DocumentImportSheet(
                pdfURL: wrapper.url,
                pdfData: wrapper.data,
                student: student,
                onSave: {
                    // Reload is handled automatically by SwiftData observing student.documents
                }
            )
        }
        .sheet(isPresented: $showRenameAlert) {
            renameSheet
        }
        .onChange(of: previewURL) { _, newURL in
            if let url = newURL {
                openDocumentInDefaultApp(url)
            }
        }
    }
    
    private func openDocumentInDefaultApp(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        #endif
    }
    
    private func handleDrop(_ urls: [URL]) -> Bool {
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
    
    private func deleteDocument(_ document: Document) {
        try? repository.deleteDocument(id: document.id)
    }
    
    private func renameDocument(_ document: Document) {
        documentToRename = document
        renameTitleText = document.title
        showRenameAlert = true
    }
    
    private var renameSheet: some View {
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
                    .disabled(renameTitleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveRename() {
        guard let document = documentToRename else { return }
        let trimmedTitle = renameTitleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        repository.updateDocument(id: document.id, title: trimmedTitle)
        _ = repository.save(reason: "Rename document")

        documentToRename = nil
        renameTitleText = ""
        showRenameAlert = false
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
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
    
    private func loadPDFData(from url: URL) async {
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
    private func presentMacOpenPanel() {
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

struct DocumentCard: View {
    let document: Document
    let onOpen: (URL) -> Void
    let onDelete: () -> Void
    let onRename: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PDFThumbnail(data: document.pdfData)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 120)
                .frame(alignment: .center)
                .padding(.vertical, 12)
            
            Text(document.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            Text(document.category)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.1))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = createTemporaryFileURL() {
                onOpen(url)
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            
            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }
        }
    }
    
    private func createTemporaryFileURL() -> URL? {
        guard let pdfData = document.pdfData else {
            return nil
        }
        
        // Create a temporary file URL
        let tempDir = FileManager.default.temporaryDirectory
        let sanitizedTitle = document.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
        let filename = sanitizedTitle.isEmpty ? "Document.pdf" : "\(sanitizedTitle).pdf"
        let tempURL = tempDir.appendingPathComponent(filename)
        
        do {
            // Write PDF data to temporary file
            try pdfData.write(to: tempURL)
            return tempURL
        } catch {
            return nil
        }
    }
}

struct PDFThumbnail: View {
    let data: Data?
    
    var body: some View {
        Group {
            if let pdfData = data, let pdfDocument = PDFDocument(data: pdfData),
               let firstPage = pdfDocument.page(at: 0) {
                PDFThumbnailView(page: firstPage)
            } else {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PDFThumbnailView: View {
    let page: PDFPage
    
    var body: some View {
        #if os(macOS)
        PDFPageViewRepresentable(page: page)
        #else
        PDFPageViewRepresentable(page: page)
        #endif
    }
}

#if os(macOS)
struct PDFPageViewRepresentable: NSViewRepresentable {
    let page: PDFPage

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .clear
        // Document assignment is deferred to updateNSView to avoid layout recursion
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        // Defer all document/navigation changes to next run loop to avoid layout recursion
        // PDFView internally triggers layout when documents are assigned
        let targetPage = page

        if let existingDocument = page.document {
            if nsView.document !== existingDocument {
                DispatchQueue.main.async {
                    nsView.document = existingDocument
                    nsView.go(to: targetPage)
                }
            } else if nsView.currentPage !== page {
                DispatchQueue.main.async {
                    nsView.go(to: targetPage)
                }
            }
        } else if nsView.document == nil {
            // Only create a new document if the page doesn't have one and view has no document
            DispatchQueue.main.async {
                let newDocument = PDFDocument()
                newDocument.insert(targetPage, at: 0)
                nsView.document = newDocument
            }
        }
    }
}
#else
struct PDFPageViewRepresentable: UIViewRepresentable {
    let page: PDFPage
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        
        // Check if the page already belongs to a document
        if let existingDocument = page.document {
            // Use the existing document to preserve accessibility tag structure
            pdfView.document = existingDocument
            pdfView.go(to: page)
        } else {
            // Only create a new document if the page doesn't have one
            let newDocument = PDFDocument()
            newDocument.insert(page, at: 0)
            pdfView.document = newDocument
        }
        
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .clear
        return pdfView
    }
    
    func updateUIView(_ uiView: PDFView, context: Context) {
        // Ensure the view stays in sync with the page
        if let existingDocument = page.document {
            if uiView.document !== existingDocument {
                uiView.document = existingDocument
                uiView.go(to: page)
            } else if uiView.currentPage !== page {
                uiView.go(to: page)
            }
        }
    }
}
#endif

#Preview {
    let container = ModelContainer.preview
    let context = container.mainContext
    let student = Student(firstName: "Alan", lastName: "Turing", birthday: Date(timeIntervalSince1970: 0), level: .upper)
    context.insert(student)
    return StudentFilesTab(student: student)
        .previewEnvironment(using: container)
        .padding()
}
