import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RootView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case lessons = "Lessons"
        case students = "Students"
        case planning = "Planning"
        case settings = "Settings"

        var id: String { rawValue }
    }

    @State private var selectedTab: Tab = .lessons

    var body: some View {
        VStack(spacing: 0) {
            // Top pill navigation
            HStack {
                Spacer()

                HStack(spacing: 12) {
                    ForEach(Tab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: AppTheme.FontSize.body, weight: .semibold))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .frame(minHeight: 30)
                                .background(pillBackground(for: tab))
                                .foregroundStyle(pillForeground(for: tab))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
            }
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Active view
            Group {
                switch selectedTab {
                case .lessons:
                    LessonsRootView()
                case .students:
                    StudentsRootView()
                case .planning:
                    PlanningRootView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Styling

    private func pillBackground(for tab: Tab) -> some ShapeStyle {
        if tab == selectedTab {
            return AnyShapeStyle(Color.accentColor)
        } else {
            return AnyShapeStyle(Color.platformBackground)
        }
    }

    private func pillForeground(for tab: Tab) -> some ShapeStyle {
        if tab == selectedTab {
            return AnyShapeStyle(Color.white)
        } else {
            return AnyShapeStyle(Color.primary)
        }
    }
}

// MARK: - Root views for each tab

struct LessonsRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var lessons: [Lesson]
    @State private var selectedLesson: Lesson? = nil
    @State private var showingAddLesson: Bool = false

    @State private var showingLessonCSVImporter = false
    @State private var importAlert: ImportAlert? = nil

    @State private var selectedSubject: String? = nil
    @State private var selectedGroup: String? = nil
    @State private var expandedSubjects: Set<String> = []

    @State private var pendingParsedImport: LessonCSVImporter.Parsed? = nil
    @State private var showingImportPreview: Bool = false

    @State private var subjectDragState: (from: Int?, to: Int?) = (nil, nil)
    @State private var groupDragState: [String: (from: Int?, to: Int?)] = [:]

    private struct ImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private var subjects: [String] {
        let unique = Set(lessons.map { $0.subject.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let existing = Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return FilterOrderStore.loadSubjectOrder(existing: existing)
    }

    private var filteredLessons: [Lesson] {
        var base = lessons
        if let subject = selectedSubject {
            base = base.filter { $0.subject.caseInsensitiveCompare(subject) == .orderedSame }
        }
        if let group = selectedGroup {
            base = base.filter { $0.group.caseInsensitiveCompare(group) == .orderedSame }
        }
        return base
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
                        Group {
                            LessonsCardsGridView(
                                lessons: filteredLessons,
                                isManualMode: false,
                                onTapLesson: { lesson in
                                    selectedLesson = lesson
                                },
                                onReorder: nil
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                showingAddLesson = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: AppTheme.FontSize.titleXLarge))
                                    .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    showingLessonCSVImporter = true
                                } label: {
                                    Label("Import Lessons from CSV…", systemImage: "arrow.down.doc")
                                }
                            }
                            .padding()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
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
                                try? modelContext.save()
                            }
                        },
                        onClose: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                selectedLesson = nil
                            }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.98).combined(with: .opacity),
                        removal: .scale(scale: 0.98).combined(with: .opacity)
                    ))
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.9), value: selectedLesson?.id)
            }
        }
        .sheet(isPresented: $showingAddLesson) {
            AddLessonView()
        }
        .fileImporter(
            isPresented: $showingLessonCSVImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            do {
                let url = try result.get()

                // Begin security-scoped access if needed (macOS sandbox / file providers)
                let needsAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if needsAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let data = try Data(contentsOf: url)
                let parsed = try LessonCSVImporter.parse(data: data, existingLessons: lessons)
                self.pendingParsedImport = parsed
                self.showingImportPreview = true
            } catch {
                importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
            }
        }
        .alert(item: $importAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $showingImportPreview, onDismiss: {
            // Clear parsed data on dismiss
            pendingParsedImport = nil
        }) {
            if let parsed = pendingParsedImport {
                LessonImportPreviewView(parsed: parsed, onCancel: {
                    showingImportPreview = false
                }, onConfirm: { filtered in
                    do {
                        let inserted = try LessonCSVImporter.commit(parsed: filtered, into: modelContext)
                        var message = "Imported \(inserted) row(s)."
                        if filtered.potentialDuplicates.count > 0 {
                            let firstFew = filtered.potentialDuplicates.prefix(5).joined(separator: "\n• ")
                            message += "\n\nPotential duplicates detected: \(filtered.potentialDuplicates.count)."
                            if !firstFew.isEmpty {
                                message += "\n\nExamples:\n• \(firstFew)"
                            }
                        }
                        if !filtered.warnings.isEmpty {
                            message += "\n\nWarnings:\n" + filtered.warnings.joined(separator: "\n")
                        }
                        importAlert = ImportAlert(title: "CSV Import Complete", message: message)
                    } catch {
                        importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
                    }
                    showingImportPreview = false
                })
                .frame(minWidth: 620, minHeight: 520)
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filters")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            // All filter
            SidebarFilterButton(
                icon: "books.vertical.fill",
                title: "All",
                color: .accentColor,
                isSelected: selectedSubject == nil
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    selectedSubject = nil
                    selectedGroup = nil
                }
            }

            ForEach(Array(subjects.enumerated()), id: \.element) { pair in
                let index = pair.offset
                let subject = pair.element
                SidebarFilterButton(
                    icon: "folder.fill",
                    title: subject,
                    color: subjectColor(for: subject),
                    isSelected: (selectedSubject?.caseInsensitiveCompare(subject) == .orderedSame) && (selectedGroup == nil),
                    trailingIcon: "chevron.right",
                    trailingIconRotationDegrees: isExpanded(subject) ? 90 : 0,
                    trailingIconAction: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                            toggleExpanded(subject)
                        }
                    }
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                        selectedSubject = subject
                        selectedGroup = nil
                    }
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
                            color: subjectColor(for: subject),
                            isSelected: (selectedSubject?.caseInsensitiveCompare(subject) == .orderedSame) && (selectedGroup?.caseInsensitiveCompare(group) == .orderedSame)
                        ) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                                selectedSubject = subject
                                selectedGroup = group
                                if !isExpanded(subject) { toggleExpanded(subject) }
                            }
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
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let unique = Set(
            lessons
                .filter { $0.subject.caseInsensitiveCompare(trimmedSubject) == .orderedSame }
                .map { $0.group.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let existing = Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return FilterOrderStore.loadGroupOrder(for: trimmedSubject, existing: existing)
    }

    private func isExpanded(_ subject: String) -> Bool {
        expandedSubjects.contains(subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private func toggleExpanded(_ subject: String) {
        let key = subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if expandedSubjects.contains(key) {
            expandedSubjects.remove(key)
        } else {
            expandedSubjects.insert(key)
        }
    }

    private func subjectColor(for subject: String) -> Color {
        AppColors.color(forSubject: subject)
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

    struct SubjectDropDelegate: DropDelegate {
        let index: Int
        let currentItems: [String]
        @Binding var dragState: (from: Int?, to: Int?)
        let onReorder: (Int, Int) -> Void

        func validateDrop(info: DropInfo) -> Bool { true }
        func dropEntered(info: DropInfo) {
            guard let from = dragState.from, from != index else { return }
            dragState.to = index
        }
        func performDrop(info: DropInfo) -> Bool {
            guard let from = dragState.from, let to = dragState.to else { dragState = (nil,nil); return false }
            dragState = (nil,nil)
            if from != to { onReorder(from, to) }
            return true
        }
    }

    struct GroupDropDelegate: DropDelegate {
        let subject: String
        let index: Int
        let currentItems: [String]
        @Binding var dragState: (from: Int?, to: Int?)
        let onReorder: (Int, Int) -> Void

        func validateDrop(info: DropInfo) -> Bool { true }
        func dropEntered(info: DropInfo) {
            guard let from = dragState.from, from != index else { return }
            dragState.to = index
        }
        func performDrop(info: DropInfo) -> Bool {
            guard let from = dragState.from, let to = dragState.to else { dragState = (nil,nil); return false }
            dragState = (nil,nil)
            if from != to { onReorder(from, to) }
            return true
        }
    }
}

struct StudentsRootView: View {
    var body: some View {
        StudentsView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlanningRootView: View {
    var body: some View {
        PlanningWeekView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

