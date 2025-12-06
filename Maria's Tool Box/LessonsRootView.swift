import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers

struct LessonsRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var lessons: [Lesson]
    @Query private var studentLessons: [StudentLesson]
    @State private var selectedLesson: Lesson? = nil

    @State private var importAlert: ImportAlert? = nil
    @State private var showingLessonCSVImporter: Bool = false
    @State private var filteredLessonsCache: [Lesson] = []
    @State private var groupsCache: [String: [String]] = [:]

    @SceneStorage("Lessons.selectedSubject") private var lessonsSelectedSubjectRaw: String = ""
    @SceneStorage("Lessons.selectedGroup") private var lessonsSelectedGroupRaw: String = ""
    @SceneStorage("Lessons.searchText") private var lessonsSearchTextRaw: String = ""
    @SceneStorage("Lessons.expandedSubjects") private var lessonsExpandedSubjectsRaw: String = ""

    private enum PresentedSheet: Identifiable {
        case addLesson(defaultSubject: String?, defaultGroup: String?)
        case bulkEntry(defaultSubject: String?, defaultGroup: String?)
        case studentLessonDraft(UUID)
        case importPreview(parsed: LessonCSVImporter.Parsed)

        var id: String {
            switch self {
            case .addLesson: return "addLesson"
            case .bulkEntry: return "bulkEntry"
            case .studentLessonDraft(let id): return "studentLessonDraft_\(id.uuidString)"
            case .importPreview: return "importPreview"
            }
        }
    }

    @State private var presentedSheet: PresentedSheet? = nil

    private let viewModel = LessonsViewModel()

    private struct ImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private var subjects: [String] {
        viewModel.subjects(from: lessons)
    }

    private var filteredLessons: [Lesson] { filteredLessonsCache }

    private var isManualMode: Bool {
        (filterState.selectedGroup != nil) && filterState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var lessonIDs: [UUID] {
        lessons.map { $0.id }
    }

    @StateObject private var filterState = LessonsFilterState()

    @State private var subjectDragState: (from: Int?, to: Int?) = (nil, nil)
    @State private var groupDragState: [String: (from: Int?, to: Int?)] = [:]
    @State private var isParsing: Bool = false
    @State private var parsingTask: Task<Void, Never>? = nil

    @ViewBuilder
    private var selectedLessonOverlay: some View {
        if let selected = selectedLesson {
            ZStack {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            selectedLesson = nil
                        }
                    }

                LessonDetailCard(
                    lesson: selected,
                    onSave: { updated in
                        if let existing = lessons.first(where: { $0.id == updated.id }) {
                            existing.name = updated.name
                            existing.subject = updated.subject
                            existing.group = updated.group
                            existing.subheading = updated.subheading
                            existing.writeUp = updated.writeUp
                            do {
                                try modelContext.save()
                            } catch {
                                importAlert = ImportAlert(title: "Save Failed", message: error.localizedDescription)
                            }
                        }
                    },
                    onClose: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            selectedLesson = nil
                        }
                    },
                    onGiveLesson: { _ in
                        presentedSheet = nil
                        let newSL = StudentLesson(
                            id: UUID(),
                            lessonID: selected.id,
                            studentIDs: [],
                            createdAt: Date(),
                            scheduledFor: nil,
                            givenAt: nil,
                            notes: "",
                            needsPractice: false,
                            needsAnotherPresentation: false,
                            followUpWork: ""
                        )
                        newSL.lesson = selected
                        newSL.syncSnapshotsFromRelationships()
                        modelContext.insert(newSL)
                        try? modelContext.save()
                        presentedSheet = .studentLessonDraft(newSL.id)
                    },
                    initialMode: .normal
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.98).combined(with: .opacity),
                    removal: .scale(scale: 0.98).combined(with: .opacity)
                ))
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: selectedLesson?.id)
        }
    }

    private func handleFileImportResult(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            // Cancel any in-flight parsing task
            parsingTask?.cancel()
            isParsing = true
            parsingTask = LessonsImportCoordinator.startImport(from: url, lessons: self.lessons, onParsed: { parsed in
                self.presentedSheet = .importPreview(parsed: parsed)
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

    private func recomputeFilteredLessons() {
        filteredLessonsCache = viewModel.filteredLessons(
            lessons: lessons,
            searchText: filterState.searchText,
            selectedSubject: filterState.selectedSubject,
            selectedGroup: filterState.selectedGroup
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar

                Divider()

                Group {
                    if lessons.isEmpty {
                        VStack(spacing: 8) {
                            Text("No lessons yet")
                                .font(.system(size: AppTheme.FontSize.titleMedium, weight: .semibold, design: .rounded))
                            Text("Create your first lesson to get started.")
                                .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear(perform: seedSamplesOnce)
                    } else {
                        LessonsCardsGridView(
                            lessons: filteredLessons,
                            isManualMode: isManualMode,
                            onTapLesson: { (lesson: Lesson) in
                                selectedLesson = lesson
                            },
                            onReorder: { (movingLesson: Lesson, fromIndex: Int, toIndex: Int, subset: [Lesson]) in
                                reorderLessons(movingLesson: movingLesson, fromIndex: fromIndex, toIndex: toIndex, subset: subset)
                            },
                            onGiveLesson: { (lesson: Lesson) in
                                presentedSheet = nil
                                let newSL = StudentLesson(
                                    id: UUID(),
                                    lessonID: lesson.id,
                                    studentIDs: [],
                                    createdAt: Date(),
                                    scheduledFor: nil,
                                    givenAt: nil,
                                    notes: "",
                                    needsPractice: false,
                                    needsAnotherPresentation: false,
                                    followUpWork: ""
                                )
                                newSL.lesson = lesson
                                newSL.syncSnapshotsFromRelationships()
                                modelContext.insert(newSL)
                                try? modelContext.save()
                                presentedSheet = .studentLessonDraft(newSL.id)
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .topTrailing) { plusMenuOverlay }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            selectedLessonOverlay
        }
        .overlay {
            ParsingOverlay(isParsing: $isParsing) {
                parsingTask?.cancel()
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .addLesson(let subject, let group):
                AddLessonView(defaultSubject: subject, defaultGroup: group)
            case .bulkEntry(let subject, let group):
                BulkLessonsEntryView(defaultSubject: subject, defaultGroup: group, onDone: {
                    presentedSheet = nil
                })
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 560)
                .presentationSizing(.fitted)
                #else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
            case .studentLessonDraft(let id):
                if let sl = studentLessons.first(where: { $0.id == id }) {
                    StudentLessonDetailView(studentLesson: sl, onDone: {
                        presentedSheet = nil
                    })
                    #if os(macOS)
                    .frame(minWidth: 720, minHeight: 640)
                    .presentationSizing(.fitted)
                    #else
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    #endif
                } else {
                    EmptyView()
                }
            case .importPreview(let parsed):
                LessonImportPreviewView(parsed: parsed, onCancel: {
                    presentedSheet = nil
                }, onConfirm: { filtered in
                    do {
                        let result = try ImportCommitService.commitLessons(parsed: filtered, into: modelContext, existingLessons: lessons)
                        importAlert = ImportAlert(title: result.title, message: result.message)
                    } catch {
                        importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
                    }
                    presentedSheet = nil
                })
                .frame(minWidth: 620, minHeight: 520)
            }
        }
        .fileImporter(
            isPresented: $showingLessonCSVImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            handleFileImportResult(result)
        }
        .alert(item: $importAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NewLessonRequested"))) { _ in
            presentedSheet = .addLesson(defaultSubject: filterState.selectedSubject, defaultGroup: filterState.selectedGroup)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ImportLessonsRequested"))) { _ in
            showingLessonCSVImporter = true
        }
        .onAppear {
            // Restore persisted filters into the observable state
            filterState.loadFromPersisted(subjectRaw: lessonsSelectedSubjectRaw, groupRaw: lessonsSelectedGroupRaw, searchRaw: lessonsSearchTextRaw, expandedRaw: lessonsExpandedSubjectsRaw)
            // If a child group is selected, ensure its parent subject is expanded so the selection is visible
            if let subject = filterState.selectedSubject, filterState.selectedGroup != nil {
                filterState.expandedSubjects.insert(LessonsFilterPersistence.normalizeSubjectKey(subject))
            }
            // Persist any adjustments back to SceneStorage
            let persisted = filterState.makePersisted()
            lessonsSelectedSubjectRaw = persisted.subjectRaw
            lessonsSelectedGroupRaw = persisted.groupRaw
            lessonsSearchTextRaw = persisted.searchRaw
            lessonsExpandedSubjectsRaw = persisted.expandedRaw

            // Defer heavier work until after the first frame to keep the UI responsive
            DispatchQueue.main.async {
                ensureInitialOrderInGroupIfNeeded()
                recomputeFilteredLessons()
            }
        }
        .onChange(of: lessonIDs) { _, _ in
            groupsCache.removeAll()
            ensureInitialOrderInGroupIfNeeded()
            recomputeFilteredLessons()
        }
        .onChange(of: filterState.selectedSubject) { _, newValue in
            lessonsSelectedSubjectRaw = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            recomputeFilteredLessons()
        }
        .onChange(of: filterState.selectedGroup) { _, newValue in
            lessonsSelectedGroupRaw = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            recomputeFilteredLessons()
        }
        .onChange(of: filterState.searchText) { _, newValue in
            lessonsSearchTextRaw = newValue
            recomputeFilteredLessons()
        }
        .onChange(of: filterState.expandedSubjects) { _, newValue in
            lessonsExpandedSubjectsRaw = LessonsFilterPersistence.serializeExpandedSubjects(newValue)
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filters")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            // Search field replacing the previous "All" filter
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search all lessons", text: $filterState.searchText)
                    .textFieldStyle(.plain)
                if !filterState.searchText.isEmpty {
                    Button {
                        filterState.searchText = ""
                        recomputeFilteredLessons()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )

            ForEach(Array(subjects.enumerated()), id: \.element) { pair in
                let index = pair.offset
                let subject = pair.element
                SidebarFilterButton(
                    icon: "folder.fill",
                    title: subject,
                    color: AppColors.color(forSubject: subject),
                    isSelected: (filterState.selectedSubject?.caseInsensitiveCompare(subject) == .orderedSame) && (filterState.selectedGroup == nil),
                    trailingIcon: "chevron.right",
                    trailingIconRotationDegrees: isExpanded(subject) ? 90 : 0,
                    trailingIconAction: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                            toggleExpanded(subject)
                        }
                        let key = LessonsFilterPersistence.normalizeSubjectKey(subject)
                        if groupsCache[key] == nil {
                            let computed = viewModel.groups(for: subject, lessons: lessons)
                            DispatchQueue.main.async {
                                groupsCache[key] = computed
                            }
                        }
                    }
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                        // Clear any active search so the subject filter takes effect immediately
                        filterState.searchText = ""
                        filterState.selectedSubject = subject
                        filterState.selectedGroup = nil
                    }
                    recomputeFilteredLessons()
                }
                .onDrag {
                    self.subjectDragState.from = index
                    return NSItemProvider(object: NSString(string: subject))
                }
                .onDrop(of: [UTType.text], delegate: SubjectDropDelegate(
                    index: index,
                    currentItems: subjects,
                    dragState: $subjectDragState,
                    onReorder: { from, to in
                        var new = subjects
                        let item = new.remove(at: from)
                        new.insert(item, at: to)
                        FilterOrderStore.saveSubjectOrder(new)
                    }
                ))

                if isExpanded(subject) {
                    let groupsForSubject = groups(for: subject)
                    ForEach(Array(groupsForSubject.enumerated()), id: \.element) { gpair in
                        let gindex = gpair.offset
                        let group = gpair.element
                        SidebarFilterButton(
                            icon: "tag.fill",
                            title: group,
                            color: AppColors.color(forSubject: subject),
                            isSelected: (filterState.selectedSubject?.caseInsensitiveCompare(subject) == .orderedSame) && (filterState.selectedGroup?.caseInsensitiveCompare(group) == .orderedSame)
                        ) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                                // Clear any active search so the group filter takes effect immediately
                                filterState.searchText = ""
                                filterState.selectedSubject = subject
                                filterState.selectedGroup = group
                                if !isExpanded(subject) { toggleExpanded(subject) }
                            }
                            recomputeFilteredLessons()
                        }
                        .padding(.leading, 16)
                        .onDrag {
                            self.groupDragState[subject, default: (nil,nil)].from = gindex
                            return NSItemProvider(object: NSString(string: group))
                        }
                        .onDrop(of: [UTType.text], delegate: GroupDropDelegate(
                            subject: subject,
                            index: gindex,
                            currentItems: groupsForSubject,
                            dragState: Binding(get: {
                                groupDragState[subject, default: (nil,nil)]
                            }, set: { newValue in
                                groupDragState[subject] = newValue
                            }),
                            onReorder: { from, to in
                                var new = groupsForSubject
                                let item = new.remove(at: from)
                                new.insert(item, at: to)
                                FilterOrderStore.saveGroupOrder(new, for: subject)
                                let key = LessonsFilterPersistence.normalizeSubjectKey(subject)
                                groupsCache[key] = new
                            }
                        ))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .padding(.leading, 16)
        .frame(width: 180, alignment: .topLeading)
        .background(Color.gray.opacity(0.08))
    }

    private func groups(for subject: String) -> [String] {
        let key = LessonsFilterPersistence.normalizeSubjectKey(subject)
        if let cached = groupsCache[key] { return cached }
        return viewModel.groups(for: subject, lessons: lessons)
    }

    private func ensureInitialOrderInGroupIfNeeded() {
        if viewModel.ensureInitialOrderInGroupIfNeeded(lessons) {
            do {
                try modelContext.save()
            } catch {
                importAlert = ImportAlert(title: "Save Failed", message: error.localizedDescription)
            }
        }
    }

    private func reorderLessons(movingLesson: Lesson, fromIndex: Int, toIndex: Int, subset: [Lesson]) {
        // Only allow reordering when a group is selected (subset corresponds to the full group for the selected subject)
        guard filterState.selectedGroup != nil else { return }
        do {
            try LessonsReorderService.reorder(movingLesson: movingLesson, fromIndex: fromIndex, toIndex: toIndex, subset: subset, context: modelContext)
        } catch {
            importAlert = ImportAlert(title: "Save Failed", message: error.localizedDescription)
        }
    }

    private func isExpanded(_ subject: String) -> Bool {
        filterState.expandedSubjects.contains(LessonsFilterPersistence.normalizeSubjectKey(subject))
    }

    private func toggleExpanded(_ subject: String) {
        let key = LessonsFilterPersistence.normalizeSubjectKey(subject)
        if filterState.expandedSubjects.contains(key) {
            filterState.expandedSubjects.remove(key)
        } else {
            filterState.expandedSubjects.insert(key)
        }
    }

    private func seedSamplesOnce() {
        guard lessons.isEmpty else { return }
        let samples = [
            Lesson(name: "Decimal System", subject: "Math", group: "Number Work", subheading: "Intro to base-10", writeUp: "A foundational presentation of the decimal system."),
            Lesson(name: "Parts of Speech", subject: "Language", group: "Grammar", subheading: "Nouns and Verbs", writeUp: "Identify and classify parts of speech in simple sentences.")
        ]
        for l in samples { modelContext.insert(l) }
        try? modelContext.save()
    }

    private var plusMenuOverlay: some View {
        Menu {
            Button {
                presentedSheet = .addLesson(defaultSubject: filterState.selectedSubject, defaultGroup: filterState.selectedGroup)
            } label: {
                Label("Add Lesson", systemImage: "text.book.closed")
            }
            Button {
                presentedSheet = .bulkEntry(defaultSubject: filterState.selectedSubject, defaultGroup: filterState.selectedGroup)
            } label: {
                Label("Bulk Entry…", systemImage: "square.grid.3x3")
            }
            Button {
                let baseLesson = (filteredLessons.first ?? lessons.first)
                let lessonID = baseLesson?.id ?? UUID()
                let newSL = StudentLesson(
                    id: UUID(),
                    lessonID: lessonID,
                    studentIDs: [],
                    createdAt: Date(),
                    scheduledFor: nil,
                    givenAt: nil,
                    notes: "",
                    needsPractice: false,
                    needsAnotherPresentation: false,
                    followUpWork: ""
                )
                if let base = baseLesson { newSL.lesson = base }
                newSL.syncSnapshotsFromRelationships()
                modelContext.insert(newSL)
                try? modelContext.save()
                presentedSheet = .studentLessonDraft(newSL.id)
            } label: {
                Label("Add Student Lesson", systemImage: "person.crop.circle.badge.plus")
            }
            Button {
                showingLessonCSVImporter = true
            } label: {
                Label("Import Lessons from CSV…", systemImage: "arrow.down.doc")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: AppTheme.FontSize.titleXLarge))
                .foregroundStyle(.green)
        }
        .buttonStyle(.plain)
        .padding()
    }
}

