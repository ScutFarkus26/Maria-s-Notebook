import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct StudentsRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var students: [Student]

    @State private var showingAddStudent: Bool = false
    @State private var showingStudentCSVImporter: Bool = false
    @State private var importAlert: ImportAlert? = nil

    @State private var mappingHeaders: [String] = []
    @State private var pendingMapping: StudentCSVImporter.Mapping? = nil
    @State private var pendingFileURL: URL? = nil
    @State private var pendingParsedImport: StudentCSVImporter.Parsed? = nil
    @State private var showingMappingSheet: Bool = false

    @State private var isParsing: Bool = false
    @State private var parsingTask: Task<Void, Never>? = nil

    private struct ImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private enum Mode: String, CaseIterable, Identifiable { 
        case roster = "Roster"
        case attendance = "Attendance"
        var id: String { rawValue }
    }

    @AppStorage("StudentsRootView.mode") private var modeRaw: String = Mode.roster.rawValue
    private var mode: Mode { Mode(rawValue: modeRaw) ?? .roster }

    var body: some View {
        VStack(spacing: 0) {
            // Top pill navigation (Roster / Attendance)
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    PillNavButton(title: Mode.attendance.rawValue, isSelected: mode == .attendance) { modeRaw = Mode.attendance.rawValue }
                    PillNavButton(title: Mode.roster.rawValue, isSelected: mode == .roster) { modeRaw = Mode.roster.rawValue }
                }
                Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, 8)

            Divider()

            Group {
                if mode == .roster {
                    rosterContent
                } else {
                    AttendanceView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Allow external triggers to jump straight to Attendance mode
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenAttendanceRequested"))) { _ in
            modeRaw = Mode.attendance.rawValue
        }
    }

    private var rosterContent: some View {
        StudentsView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                Button {
                    showingAddStudent = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: AppTheme.FontSize.titleXLarge))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        showingStudentCSVImporter = true
                    } label: {
                        Label("Import Students from CSV…", systemImage: "arrow.down.doc")
                    }
                }
                .padding()
            }
            .overlay {
                ParsingOverlay(isParsing: $isParsing) {
                    parsingTask?.cancel()
                }
            }
            .sheet(isPresented: $showingAddStudent) {
                AddStudentView()
            }
            .fileImporter(
                isPresented: $showingStudentCSVImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText]
            ) { result in
                do {
                    let url = try result.get()
                    parsingTask?.cancel()
                    isParsing = true
                    parsingTask = StudentsImportCoordinator.startHeaderScan(from: url, onParsed: { headers, mapping in
                        self.pendingFileURL = url
                        self.mappingHeaders = headers
                        self.pendingMapping = mapping
                        self.showingMappingSheet = true
                    }, onError: { error in
                        self.importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
                    }, onFinally: {
                        self.isParsing = false
                        self.parsingTask = nil
                    })
                } catch {
                    importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
                    isParsing = false
                    parsingTask = nil
                }
            }
            .sheet(isPresented: $showingMappingSheet) {
                StudentCSVMappingView(headers: mappingHeaders, onCancel: {
                    showingMappingSheet = false
                    pendingFileURL = nil
                }, onConfirm: { mapping in
                    // Ensure we have a file URL before starting the background work
                    guard let fileURL = pendingFileURL else { return }
                    parsingTask?.cancel()
                    isParsing = true
                    parsingTask = StudentsImportCoordinator.startMappedParse(from: fileURL, mapping: mapping, students: self.students, onParsed: { parsed in
                        self.pendingParsedImport = parsed
                        self.showingMappingSheet = false
                    }, onError: { error in
                        self.importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
                        self.showingMappingSheet = false
                    }, onFinally: {
                        self.isParsing = false
                        self.parsingTask = nil
                    })
                })
            }
            .sheet(item: $pendingParsedImport, onDismiss: {
                pendingFileURL = nil
            }) { parsed in
                StudentImportPreviewView(parsed: parsed, onCancel: {
                    pendingParsedImport = nil
                }, onConfirm: { filtered in
                    do {
                        let result = try ImportCommitService.commitStudents(parsed: filtered, into: modelContext, existingStudents: students)
                        importAlert = ImportAlert(title: result.title, message: result.message)
                    } catch {
                        importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
                    }
                    pendingParsedImport = nil
                })
                .frame(minWidth: 620, minHeight: 520)
            }
            .alert(item: $importAlert) { alert in
                Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NewStudentRequested"))) { _ in
                showingAddStudent = true
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ImportStudentsRequested"))) { _ in
                showingStudentCSVImporter = true
            }
    }
}
