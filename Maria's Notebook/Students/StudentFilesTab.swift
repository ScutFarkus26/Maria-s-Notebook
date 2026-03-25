import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum DocumentSortOption {
    case dateDesc
    case dateAsc
    case title
}

struct StudentFilesTab: View {
    static let logger = Logger.students

    let student: Student

    @Environment(\.modelContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    var repository: DocumentRepository {
        DocumentRepository(context: modelContext, saveCoordinator: saveCoordinator)
    }

    @State private var showFileImporter = false
    @State var selectedImportData: ImportDataWrapper?
    @State var documentToRename: Document?
    @State var showRenameAlert = false
    @State var renameTitleText = ""
    @State private var previewURL: URL?
    @State private var sortOption: DocumentSortOption = .dateDesc
    @State private var filterCategory: String?

    struct ImportDataWrapper: Identifiable {
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
        let categories = Set(allDocuments.map(\.category))
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
                                    Label("All", systemImage: SFSymbol.Document.folder)
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
                                    Label("Date (Newest)", systemImage: SFSymbol.Time.calendar)
                                    if sortOption == .dateDesc {
                                        Image(systemName: "checkmark")
                                    }
                                }

                                Button {
                                    sortOption = .dateAsc
                                } label: {
                                    Label("Date (Oldest)", systemImage: SFSymbol.Time.calendar)
                                    if sortOption == .dateAsc {
                                        Image(systemName: "checkmark")
                                    }
                                }

                                Button {
                                    sortOption = .title
                                } label: {
                                    Label("Title", systemImage: SFSymbol.Text.textformat)
                                    if sortOption == .title {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        } label: {
                            Label("Filter & Sort", systemImage: SFSymbol.Search.lineHorizontal3DecreaseCircle)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            #if os(macOS)
                            presentMacOpenPanel()
                            #else
                            showFileImporter = true
                            #endif
                        } label: {
                            Label("Add File", systemImage: SFSymbol.Action.plusCircleFill)
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
            .dropDestination(for: URL.self) { items, _ in
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
}

private enum StudentFilesTabPreviewFactory {
    @MainActor
    static func makeView() -> some View {
        let container = ModelContainer.preview
        let context = container.mainContext
        let student = Student(
            firstName: "Alan", lastName: "Turing",
            birthday: Date(timeIntervalSince1970: 0), level: .upper
        )
        context.insert(student)
        return StudentFilesTab(student: student)
            .previewEnvironment(using: container)
            .padding()
    }
}

#Preview {
    StudentFilesTabPreviewFactory.makeView()
}
