import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers

struct LessonsRootView: View {
    @StateObject private var vm = LessonsRootViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appRouter) private var appRouter
    @EnvironmentObject private var saveCoordinator: SaveCoordinator
    
    // OPTIMIZATION: Use lightweight query for studentLessons change detection only (IDs only)
    // Extract IDs immediately to avoid retaining full objects - significantly reduces memory usage
    @Query(sort: [SortDescriptor(\Lesson.id)]) private var lessons: [Lesson]
    @Query(sort: [SortDescriptor(\StudentLesson.id)]) private var studentLessonsForChangeDetection: [StudentLesson]
    
    // MEMORY OPTIMIZATION: Extract only IDs for change detection to avoid loading full objects
    private var studentLessonIDs: [UUID] {
        studentLessonsForChangeDetection.map { $0.id }
    }
    
    @State private var selectedLesson: Lesson? = nil
    
    // OPTIMIZATION: Cache studentLessons only for filtered lessons
    @State private var cachedStudentLessons: [StudentLesson] = []

    @State private var importAlert: ImportAlert? = nil
    @State private var showingLessonCSVImporter: Bool = false
    @State private var groupsCache: [String: [String]] = [:]

    @SceneStorage("Lessons.selectedSubject") private var lessonsSelectedSubjectRaw: String = ""
    @SceneStorage("Lessons.selectedGroup") private var lessonsSelectedGroupRaw: String = ""
    @SceneStorage("Lessons.searchText") private var lessonsSearchTextRaw: String = ""
    @SceneStorage("Lessons.expandedSubjects") private var lessonsExpandedSubjectsRaw: String = ""
    @SceneStorage("Lessons.sourceFilter") private var lessonsSourceRaw: String = ""
    @SceneStorage("Lessons.personalKindFilter") private var lessonsPersonalKindRaw: String = ""

    private enum PresentedSheet: Identifiable {
        case addLesson(defaultSubject: String?, defaultGroup: String?)
        case bulkEntry(defaultSubject: String?, defaultGroup: String?)
        case studentLessonDraft(UUID)
        case importPreview(parsed: LessonCSVImporter.Parsed)
        case lessonDetails(UUID)

        var id: String {
            switch self {
            case .addLesson: return "addLesson"
            case .bulkEntry: return "bulkEntry"
            case .studentLessonDraft(let id): return "studentLessonDraft_\(id.uuidString)"
            case .importPreview: return "importPreview"
            case .lessonDetails(let id): return "lessonDetails_\(id.uuidString)"
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

    private var filteredLessons: [Lesson] { vm.filteredLessons }

    private var isManualMode: Bool {
        (filterState.selectedGroup != nil) && filterState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var lessonIDs: [UUID] {
        lessons.map { $0.id }
    }
    private var lessonsFingerprint: String {
        lessons.map { lesson in
            [
                lesson.id.uuidString,
                lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                lesson.group.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                String(lesson.orderInGroup)
            ].joined(separator: "|")
        }.joined(separator: ";")
    }

    private var lessonNeedsCounts: [UUID: Int] {
        // OPTIMIZATION: Use cached studentLessons (only for filtered lessons) instead of all studentLessons
        let grouped: [UUID: [StudentLesson]] = cachedStudentLessons.grouped { $0.resolvedLessonID }
        let counts: [UUID: Int] = grouped.mapValues { (list: [StudentLesson]) in
            list.filter { !$0.isGiven }.count
        }
        return counts
    }

    @StateObject private var filterState = LessonsFilterState()

    @State private var subjectDragState: (from: Int?, to: Int?) = (nil, nil)
    @State private var groupDragState: [String: (from: Int?, to: Int?)] = [:]
    @State private var isParsing: Bool = false
    @State private var parsingTask: Task<Void, Never>? = nil

    var body: some View {
        let base = rootLayout
        let withSelected = base.overlay { selectedLessonOverlay }
        let withParsing = withSelected.overlay { parsingOverlay }
        // Fix: Use 'isPresented' to avoid ambiguity between standard 'sheet(item:)' and 'SheetPresentationHelpers' extension
        let withSheet = withParsing.sheet(isPresented: Binding(
            get: { presentedSheet != nil },
            set: { if !$0 { presentedSheet = nil } }
        )) {
            if let sheet = presentedSheet {
                viewForSheet(sheet)
            }
        }
        let withImporter = withSheet.fileImporter(
            isPresented: $showingLessonCSVImporter,
            allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText]
        ) { result in
            handleFileImportResult(result)
        }
        let withAlert = withImporter.alert(item: $importAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        let withNotifications = withAlert
            .onChange(of: appRouter.navigationDestination) { _, destination in
                if case .newLesson(let defaultSubject, let defaultGroup) = destination {
                    presentedSheet = .addLesson(
                        defaultSubject: defaultSubject ?? filterState.selectedSubject,
                        defaultGroup: defaultGroup ?? filterState.selectedGroup
                    )
                    appRouter.clearNavigation()
                } else if case .importLessons = destination {
                    showingLessonCSVImporter = true
                    appRouter.clearNavigation()
                }
            }
            .onAppear {
                // Restore persisted filters into the observable state
                filterState.loadFromPersisted(subjectRaw: lessonsSelectedSubjectRaw, groupRaw: lessonsSelectedGroupRaw, searchRaw: lessonsSearchTextRaw, expandedRaw: lessonsExpandedSubjectsRaw, sourceRaw: lessonsSourceRaw, personalKindRaw: lessonsPersonalKindRaw)
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
                lessonsSourceRaw = persisted.sourceRaw
                lessonsPersonalKindRaw = persisted.personalKindRaw

                // Defer heavier work until after the first frame to keep the UI responsive
                DispatchQueue.main.async {
                    ensureInitialOrderInGroupIfNeeded()
                    recomputeFilteredLessons()
                    updateCachedStudentLessons()
                }
            }
            .onChange(of: lessonIDs) { _, _ in
                groupsCache.removeAll()
                ensureInitialOrderInGroupIfNeeded()
                recomputeFilteredLessons()
            }
            .onChange(of: lessonsFingerprint) { _, _ in
                // React to subject/group/order changes so the grid updates immediately
                groupsCache.removeAll()
                recomputeFilteredLessons()
            }
            .onChange(of: filterState.selectedSubject) { _, newValue in
                lessonsSelectedSubjectRaw = newValue?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
                recomputeFilteredLessons()
            }
            .onChange(of: filterState.selectedGroup) { _, newValue in
                lessonsSelectedGroupRaw = newValue?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
                recomputeFilteredLessons()
            }
            .onChange(of: filterState.searchText) { _, newValue in
                lessonsSearchTextRaw = newValue
                recomputeFilteredLessons()
            }
            .onChange(of: filterState.expandedSubjects) { _, newValue in
                lessonsExpandedSubjectsRaw = LessonsFilterPersistence.serializeExpandedSubjects(newValue)
            }
        return withNotifications
    }

    private var rootLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar

                Divider()

                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var parsingOverlay: some View {
        ParsingOverlay(isParsing: $isParsing) {
            parsingTask?.cancel()
        }
    }

    private func cacheKey(for subject: String) -> String {
        let norm = LessonsFilterPersistence.normalizeSubjectKey(subject)
        let sourcePart = filterState.sourceFilter?.rawValue ?? "all"
        let kindPart = filterState.personalKindFilter?.rawValue ?? "any"
        return [norm, sourcePart, kindPart].joined(separator: "|")
    }

    private var sidebar: some View {
        ScrollView(.vertical, showsIndicators: true) {
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

                ForEach(subjects.indices, id: \.self) { i in
                    subjectSection(for: i, subject: subjects[i])
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 16)
            .padding(.leading, 16)
        }
        .frame(width: 180, alignment: .topLeading)
        .background(Color.gray.opacity(0.08))
    }

    @ViewBuilder
    private var lessonsMainContent: some View {
        let onTap: (Lesson) -> Void = { lesson in
            presentedSheet = .lessonDetails(lesson.id)
        }
        let onReorder: (Lesson, Int, Int, [Lesson]) -> Void = { movingLesson, fromIndex, toIndex, subset in
            reorderLessons(movingLesson: movingLesson, fromIndex: fromIndex, toIndex: toIndex, subset: subset)
        }
        let onGive: (Lesson) -> Void = { lesson in
            presentedSheet = nil
            let newSL = vm.createStudentLesson(basedOn: lesson, in: modelContext)
            presentedSheet = .studentLessonDraft(newSL.id)
        }

        let grid = LessonsCardsGridView(
            lessons: filteredLessons,
            isManualMode: isManualMode,
            onTapLesson: onTap,
            onReorder: onReorder,
            onGiveLesson: onGive,
            statusCounts: lessonNeedsCounts,
            selectedSubject: filterState.selectedSubject
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        grid
    }

    @ViewBuilder
    private var contentArea: some View {
        if lessons.isEmpty {
            emptyStateView
        } else {
            mainContentOverlay
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Text("No lessons yet")
                .font(.system(size: AppTheme.FontSize.titleMedium, weight: .semibold, design: .rounded))
            Text("Create your first lesson to get started.")
                .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { vm.seedSamplesIfNeeded(lessons: lessons, into: modelContext) }
    }

    private var mainContentOverlay: some View {
        lessonsMainContent
            .safeAreaInset(edge: .top) {
                ZStack {
                    // Align controls to the trailing edge
                    HStack { Spacer(); toolbarContent }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
                .overlay(alignment: .bottom) { Divider() }
            }
    }
    
    private var toolbarContent: some View {
        HStack(spacing: 12) {
            plusMenuOverlay
        }
        .padding()
    }

    @ViewBuilder
    private var selectedLessonOverlay: some View {
        if let lesson = selectedLesson {
            ZStack {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut) { selectedLesson = nil }
                    }

                VStack(alignment: .leading, spacing: 12) {
                    Text(LessonFormatter.titleOrFallback(lesson.name))
                        .font(.system(size: AppTheme.FontSize.titleMedium, weight: .semibold, design: .rounded))

                    let subtitle: String = {
                        switch (lesson.subject.isEmpty, lesson.group.isEmpty) {
                        case (false, false): return "\(lesson.subject) • \(lesson.group)"
                        case (false, true): return lesson.subject
                        case (true, false): return lesson.group
                        default: return ""
                        }
                    }()
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.easeInOut) { selectedLesson = nil }
                        } label: {
                            Label("Close", systemImage: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(16)
                .frame(maxWidth: 420)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(radius: 12)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func subjectSection(for index: Int, subject: String) -> some View {
        let isSubjectSelected: Bool = (filterState.selectedSubject?.caseInsensitiveCompare(subject) == .orderedSame) && (filterState.selectedGroup == nil)
        let subjectColor = AppColors.color(forSubject: subject)
        let expanded: Bool = isExpanded(subject)
        let onSubjectTap: () -> Void = {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                // Clear any active search so the subject filter takes effect immediately
                filterState.searchText = ""
                filterState.selectedSubject = subject
                filterState.selectedGroup = nil
            }
            recomputeFilteredLessons()
        }
        let onToggleExpand: () -> Void = {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                toggleExpanded(subject)
            }
            let key = cacheKey(for: subject)
            if groupsCache[key] == nil {
                let computed = groups(for: subject)
                DispatchQueue.main.async {
                    groupsCache[key] = computed
                }
            }
        }

        let subjectOnReorder: (Int, Int) -> Void = { from, to in
            var new = subjects
            let item = new.remove(at: from)
            new.insert(item, at: to)
            FilterOrderStore.saveSubjectOrder(new)
        }
        let subjectDropDelegate = SubjectDropDelegate(
            index: index,
            currentItems: subjects,
            dragState: $subjectDragState,
            onReorder: subjectOnReorder
        )

        SubjectRow(
            subject: subject,
            isSelected: isSubjectSelected,
            color: subjectColor,
            isExpanded: expanded,
            onTap: onSubjectTap,
            onToggleExpand: onToggleExpand
        )
        .onDrag {
            self.subjectDragState.from = index
            return NSItemProvider(object: NSString(string: subject))
        }
        .onDrop(of: [UTType.text], delegate: subjectDropDelegate)

        if isExpanded(subject) {
            groupRows(for: subject)
        }
    }

    @ViewBuilder
    private func groupRows(for subject: String) -> some View {
        let groupsForSubject: [String] = groups(for: subject)
        ForEach(groupsForSubject.indices, id: \.self) { gindex in
            let group = groupsForSubject[gindex]

            let groupColor = AppColors.color(forSubject: subject)
            let isGroupSelected: Bool = (filterState.selectedSubject?.caseInsensitiveCompare(subject) == .orderedSame) && (filterState.selectedGroup?.caseInsensitiveCompare(group) == .orderedSame)
            let onGroupTap: () -> Void = {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    // Clear any active search so the group filter takes effect immediately
                    filterState.searchText = ""
                    filterState.selectedSubject = subject
                    filterState.selectedGroup = group
                    if !isExpanded(subject) { toggleExpanded(subject) }
                }
                recomputeFilteredLessons()
            }

            let groupOnReorder: (Int, Int) -> Void = { from, to in
                var new = groupsForSubject
                let item = new.remove(at: from)
                new.insert(item, at: to)
                FilterOrderStore.saveGroupOrder(new, for: subject)
                let key = cacheKey(for: subject)
                groupsCache[key] = new
            }
            let groupDropDelegate = GroupDropDelegate(
                subject: subject,
                index: gindex,
                currentItems: groupsForSubject,
                dragState: groupDragBinding(for: subject),
                onReorder: groupOnReorder
            )

            GroupRow(
                subject: subject,
                group: group,
                isSelected: isGroupSelected,
                color: groupColor,
                onTap: onGroupTap
            )
            .onDrag {
                self.groupDragState[subject, default: (nil,nil)].from = gindex
                return NSItemProvider(object: NSString(string: group))
            }
            .onDrop(of: [UTType.text], delegate: groupDropDelegate)
        }
    }

    private func groups(for subject: String) -> [String] {
        let key = cacheKey(for: subject)
        if let cached = groupsCache[key] { return cached }
        let scoped = viewModel.filteredLessons(
            lessons: lessons,
            sourceFilter: filterState.sourceFilter,
            personalKindFilter: filterState.personalKindFilter,
            searchText: "",
            selectedSubject: nil,
            selectedGroup: nil
        )
        return viewModel.groups(for: subject, lessons: scoped)
    }

    private func ensureInitialOrderInGroupIfNeeded() {
        if viewModel.ensureInitialOrderInGroupIfNeeded(lessons) {
            _ = saveCoordinator.save(modelContext, reason: "Ensure initial order in group")
        }
    }

    private func reorderLessons(movingLesson: Lesson, fromIndex: Int, toIndex: Int, subset: [Lesson]) {
        // Only allow reordering when a group is selected (subset corresponds to the full group for the selected subject)
        guard filterState.selectedGroup != nil else { return }
        do {
            try LessonsReorderService.reorder(movingLesson: movingLesson, fromIndex: fromIndex, toIndex: toIndex, subset: subset, context: modelContext)
            _ = saveCoordinator.save(modelContext, reason: "Reorder lessons")
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

    private func groupDragBinding(for subject: String) -> Binding<(from: Int?, to: Int?)> {
        Binding<(from: Int?, to: Int?)>(
            get: { self.groupDragState[subject, default: (nil, nil)] },
            set: { self.groupDragState[subject] = $0 }
        )
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
        vm.recomputeFilteredLessons(all: lessons, filterState: filterState, using: viewModel)
        // Update cached studentLessons after filtering
        updateCachedStudentLessons()
    }
    
    // MARK: - StudentLessons Optimization
    
    /// Updates cached studentLessons to only include those for filtered lessons
    private func updateCachedStudentLessons() {
        let filteredLessonIDs = Set(vm.filteredLessons.map { $0.id })
        guard !filteredLessonIDs.isEmpty else {
            cachedStudentLessons = []
            return
        }
        
        // Fetch only studentLessons for filtered lessons
        do {
            // SwiftData predicates don't easily support filtering by resolvedLessonID (which uses relationships),
            // so we fetch all and filter in memory. This is still better than loading all studentLessons
            // reactively via @Query when we only need a subset.
            let descriptor = FetchDescriptor<StudentLesson>(
                sortBy: [SortDescriptor(\.createdAt, order: .forward)]
            )
            let allStudentLessons = try modelContext.fetch(descriptor)
            cachedStudentLessons = allStudentLessons.filter { filteredLessonIDs.contains($0.resolvedLessonID) }
        } catch {
            // Fallback: use safe fetch
            let allStudentLessons = modelContext.safeFetch(FetchDescriptor<StudentLesson>())
            cachedStudentLessons = allStudentLessons.filter { filteredLessonIDs.contains($0.resolvedLessonID) }
        }
    }

    @ViewBuilder
    private func viewForSheet(_ sheet: PresentedSheet) -> some View {
        switch sheet {
        case .addLesson(let subject, let group):
            AddLessonView(defaultSubject: subject, defaultGroup: group)
        case .bulkEntry(let subject, let group):
            BulkLessonsEntryView(defaultSubject: subject, defaultGroup: group, onDone: {
                presentedSheet = nil
            })
            #if os(macOS)
            .frame(minWidth: 720, minHeight: 560)
            .presentationSizingFitted()
            #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        case .studentLessonDraft(let id):
            if let sl = cachedStudentLessons.first(where: { $0.id == id }) ?? studentLessonsForChangeDetection.first(where: { $0.id == id }) {
                StudentLessonDetailView(studentLesson: sl, onDone: {
                    presentedSheet = nil
                })
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 640)
                .presentationSizingFitted()
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
        case .lessonDetails(let id):
            if let lesson = lessons.first(where: { $0.id == id }) {
                LessonDetailView(lesson: lesson, onSave: { _ in
                    Task { @MainActor in
                        _ = saveCoordinator.save(modelContext, reason: "Save lesson changes")
                    }
                }, onDone: {
                    presentedSheet = nil
                })
                #if os(macOS)
                .frame(minWidth: 520, minHeight: 560)
                .presentationSizingFitted()
                #else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
            } else {
                EmptyView()
            }
        }
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
                let newSL = vm.createStudentLesson(basedOn: baseLesson, in: modelContext)
                presentedSheet = .studentLessonDraft(newSL.id)
            } label: {
                Label("Add Presentation", systemImage: "person.crop.circle.badge.plus")
            }
            Button {
                showingLessonCSVImporter = true
            } label: {
                Label("Import Lessons from CSV…", systemImage: "arrow.down.doc")
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .buttonStyle(.plain)
    }

    private struct SubjectRow: View {
        let subject: String
        let isSelected: Bool
        let color: Color
        let isExpanded: Bool
        let onTap: () -> Void
        let onToggleExpand: () -> Void

        var body: some View {
            SidebarFilterButton(
                icon: "folder.fill",
                title: subject,
                color: color,
                isSelected: isSelected,
                trailingIcon: "chevron.right",
                trailingIconRotationDegrees: isExpanded ? 90 : 0,
                trailingIconAction: onToggleExpand
            ) {
                onTap()
            }
        }
    }

    private struct GroupRow: View {
        let subject: String
        let group: String
        let isSelected: Bool
        let color: Color
        let onTap: () -> Void

        var body: some View {
            SidebarFilterButton(
                icon: "tag.fill",
                title: group,
                color: color,
                isSelected: isSelected
            ) {
                onTap()
            }
            .padding(.leading, 16)
        }
    }
}

