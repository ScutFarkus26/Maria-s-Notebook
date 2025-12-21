import SwiftUI
import SwiftData
import Combine

#if os(macOS)
import AppKit
#endif

// MARK: - Student Progress Report Editor
struct StudentProgressReportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    let student: Student

    @State private var report: StudentProgressReport? = nil
    @State private var editingTerm: ReportTerm = .midYear

    // Collapsed/expanded state per domain
    @State private var expandedDomains: Set<String> = []

    // Debounced saving coordinator
    @StateObject private var saver = DebouncedSaver()
    @State private var headerAutosaveTask: Task<Void, Never>? = nil

    // Local header fields bound to report
    @State private var schoolYear: String = "2024-2025"
    @State private var teacher: String = ""
    @State private var grade: String = ""
    enum HeaderField: Hashable { case schoolYear, teacher, grade }
    @FocusState private var headerFocus: HeaderField?

    // MARK: - Init
    init(student: Student) {
        self.student = student
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ratingsEditor
                    Divider().padding(.vertical, 4)
                    commentsEditor
                    Divider().padding(.vertical, 4)
                    exportButtons
                }
                .padding(16)
            }
        }
        .onAppear { loadOrCreateReport() }
        .onChange(of: schoolYear) { _, _ in
            updateHeaderFieldsAndSave()
            saver.flushSave(context: modelContext)
        }
        .onChange(of: teacher) { _, _ in
            updateHeaderFieldsAndSave()
            saver.flushSave(context: modelContext)
        }
        .onChange(of: grade) { _, _ in
            updateHeaderFieldsAndSave()
            saver.flushSave(context: modelContext)
        }
        .onChange(of: headerFocus) { _, newFocus in
            if newFocus == nil {
                updateHeaderFieldsAndSave()
                saver.flushSave(context: modelContext)
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background || newPhase == .inactive {
                updateHeaderFieldsAndSave()
                saver.flushSave(context: modelContext)
            }
        }
        .onDisappear {
            updateHeaderFieldsAndSave()
            saver.flushSave(context: modelContext)
            headerAutosaveTask?.cancel()
        }
    }

    private func scheduleHeaderAutosaveFlush() {
        headerAutosaveTask?.cancel()
        headerAutosaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            saver.flushSave(context: modelContext)
        }
    }

    // MARK: - Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(student.fullName)
                    .font(.system(size: AppTheme.FontSize.titleMedium, weight: .bold, design: .rounded))
                Spacer()
                Picker("Term", selection: $editingTerm) {
                    Text("Mid-Year").tag(ReportTerm.midYear)
                    Text("End-of-Year").tag(ReportTerm.endYear)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
            }
            HStack(spacing: 12) {
                TextField("School Year", text: Binding(
                    get: { report?.schoolYear ?? schoolYear },
                    set: { newValue in
                        schoolYear = newValue
                        if let r = report { r.schoolYear = newValue }
                        saver.scheduleSave(context: modelContext)
                        saver.flushSave(context: modelContext)
                    }
                ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                    .focused($headerFocus, equals: .schoolYear)
                    .onSubmit {
                        if let r = report { r.schoolYear = schoolYear }
                        saver.flushSave(context: modelContext)
                    }
                TextField("Teacher", text: Binding(
                    get: { report?.teacher ?? teacher },
                    set: { newValue in
                        teacher = newValue
                        if let r = report { r.teacher = newValue }
                        saver.scheduleSave(context: modelContext)
                        saver.flushSave(context: modelContext)
                    }
                ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                    .focused($headerFocus, equals: .teacher)
                    .onSubmit {
                        if let r = report { r.teacher = teacher }
                        saver.flushSave(context: modelContext)
                    }
                TextField("Grade", text: Binding(
                    get: { report?.grade ?? grade },
                    set: { newValue in
                        grade = newValue
                        if let r = report { r.grade = newValue }
                        saver.scheduleSave(context: modelContext)
                        saver.flushSave(context: modelContext)
                    }
                ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                    .focused($headerFocus, equals: .grade)
                    .onSubmit {
                        if let r = report { r.grade = grade }
                        saver.flushSave(context: modelContext)
                    }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Ratings Editor
    private var ratingsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ratings")
                .font(.headline)
            if let r = report?.ratings {
                let grouped = groupedByDomainPreservingOrder(r)
                let filtered = grouped.filter { !["Kriah","Chumash","Kesivah","Taryag Mitzvos","Navi/Yamim Tovim"].contains($0.domain) }
                let filteredNoStoryline = filtered.map { (domain: $0.domain, entries: $0.entries.filter { $0.skillLabel.range(of: "Storyline", options: .caseInsensitive) == nil }) }
                ForEach(filteredNoStoryline, id: \.domain) { group in
                    DisclosureGroup(isExpanded: Binding(
                        get: { expandedDomains.contains(group.domain) },
                        set: { newValue in
                            if newValue { expandedDomains.insert(group.domain) } else { expandedDomains.remove(group.domain) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(group.entries, id: \.id) { entry in
                                ratingRow(entry)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text(group.domain)
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("Loading…").foregroundStyle(.secondary)
            }
        }
    }

    private func ratingRow(_ entry: ReportRatingEntry) -> some View {
        HStack(spacing: 10) {
            Text(entry.skillLabel)
                .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
            Spacer()
            // Segmented picker: blank / 4 / 3 / 2 / 1 / X
            Picker("", selection: Binding<String?>(
                get: {
                    let v = (editingTerm == .midYear) ? entry.midYear?.rawValue : entry.endYear?.rawValue
                    return v
                },
                set: { newRaw in
                    setRating(for: entry.id, valueRaw: newRaw)
                }
            )) {
                Text("—").tag(Optional<String>(nil))
                Text("4").tag(Optional("4"))
                Text("3").tag(Optional("3"))
                Text("2").tag(Optional("2"))
                Text("1").tag(Optional("1"))
                Text("X").tag(Optional("X"))
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Comments Editor
    private var commentsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(.headline)
            if let report = report {
                // Section comments
                ForEach(ProgressReportSchema.commentSections, id: \.self) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section)
                            .font(.subheadline.weight(.semibold))
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Mid-Year Comments").font(.caption).foregroundStyle(.secondary)
                                TextEditor(text: Binding<String>(
                                    get: { report.comments.midYearBySection[section] ?? "" },
                                    set: { newText in updateSectionComment(section: section, term: .midYear, value: newText) }
                                ))
                                .frame(minHeight: 80)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("End-of-Year Comments").font(.caption).foregroundStyle(.secondary)
                                TextEditor(text: Binding<String>(
                                    get: { report.comments.endYearBySection[section] ?? "" },
                                    set: { newText in updateSectionComment(section: section, term: .endYear, value: newText) }
                                ))
                                .frame(minHeight: 80)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }

                Divider().padding(.vertical, 4)

                // Mid-Year Summary
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mid-Year Summary").font(.subheadline.weight(.semibold))
                    summaryField(title: "Overview", keyPath: \.midYearOverview)
                    summaryField(title: "Strengths", keyPath: \.midYearStrengths)
                    summaryField(title: "Areas for Growth", keyPath: \.midYearAreasForGrowth)
                    summaryField(title: "Goals", keyPath: \.midYearGoals)
                    summaryField(title: "Outlook", keyPath: \.midYearOutlook)
                }

                // End-of-Year Narrative
                VStack(alignment: .leading, spacing: 8) {
                    Text("End-of-Year Narrative").font(.subheadline.weight(.semibold))
                    summaryField(title: "Overview", keyPath: \.endYearOverview)
                    summaryField(title: "Strengths", keyPath: \.endYearStrengths)
                    summaryField(title: "Challenges", keyPath: \.endYearChallenges)
                    summaryField(title: "Current Strategies and Support", keyPath: \.endYearCurrentStrategies)
                    summaryField(title: "Goals", keyPath: \.endYearGoals)
                    summaryField(title: "Outlook", keyPath: \.endYearOutlook)
                }
            }
        }
    }

    private func summaryField(title: String, keyPath: WritableKeyPath<ReportComments, String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: Binding<String>(
                get: { report?.comments[keyPath: keyPath] ?? "" },
                set: { newValue in
                    guard var r = report else { return }
                    var c = r.comments
                    c[keyPath: keyPath] = newValue
                    r.comments = c
                    report = r
                    saver.scheduleSave(context: modelContext)
                }
            ))
            .frame(minHeight: 80)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
        }
    }

    // MARK: - Export Buttons
    private var exportButtons: some View {
        HStack(spacing: 12) {
            Button {
                exportDOCX()
            } label: {
                Label("Export DOCX", systemImage: "doc")
            }
            .buttonStyle(.borderedProminent)

            Button {
                exportPDF()
            } label: {
                Label("Export PDF", systemImage: "doc.richtext")
            }
            .buttonStyle(.bordered)
            .help("Optional printable PDF")

            Spacer()
        }
    }

    // MARK: - Actions
    private func loadOrCreateReport() {
        let r = StudentProgressReportStore.fetchOrCreate(for: student.id, using: modelContext)
        report = r
        schoolYear = r.schoolYear
        teacher = r.teacher
        grade = r.grade
        // Expand common domains by default
        let defaults: [String] = ["ELA", "Math", "Behavior/Work Habits", "Navi/Yamim Tovim"]
        expandedDomains = Set(defaults)
    }

    private func updateHeaderFieldsAndSave() {
        guard var r = report else { return }
        r.schoolYear = schoolYear
        r.teacher = teacher
        r.grade = grade
        report = r
        saver.scheduleSave(context: modelContext)
    }

    private func setRating(for id: String, valueRaw: String?) {
        guard var r = report else { return }
        var entries = r.ratings
        if let idx = entries.firstIndex(where: { $0.id == id }) {
            var e = entries[idx]
            let value = valueRaw.flatMap { ReportRatingValue(rawValue: $0) }
            switch editingTerm {
            case .midYear: e.midYear = value
            case .endYear: e.endYear = value
            }
            entries[idx] = e
            r.ratings = entries
            report = r
            saver.scheduleSave(context: modelContext)
        }
    }

    private func updateSectionComment(section: String, term: ReportTerm, value: String) {
        guard var r = report else { return }
        var c = r.comments
        switch term {
        case .midYear:
            c.midYearBySection[section] = value
        case .endYear:
            c.endYearBySection[section] = value
        }
        r.comments = c
        report = r
        saver.scheduleSave(context: modelContext)
    }

    private func groupedByDomainPreservingOrder(_ entries: [ReportRatingEntry]) -> [(domain: String, entries: [ReportRatingEntry])] {
        var order: [String] = []
        var buckets: [String: [ReportRatingEntry]] = [:]
        for e in entries {
            if buckets[e.domain] == nil { order.append(e.domain); buckets[e.domain] = [] }
            buckets[e.domain]?.append(e)
        }
        return order.map { dom in (domain: dom, entries: buckets[dom] ?? []) }
    }

    private func exportDOCX() {
        guard let r = report else { return }
        saver.flushSave(context: modelContext)
        #if os(macOS)
        Task { @MainActor in
            do {
                try await ProgressReportExporter.exportDOCXViaSavePanel(report: r, student: student)
            } catch {
                presentAlert(title: "Export Failed", message: error.localizedDescription)
            }
        }
        #else
        // iOS: Not primary path; could share temp file if desired
        #endif
    }

    private func exportPDF() {
        guard let r = report else { return }
        saver.flushSave(context: modelContext)
        #if os(macOS)
        let view = ProgressReportPrintView(student: student, report: r)
        do {
            try PdfRenderer.render(view: AnyView(view), suggestedFileName: safeFileName())
        } catch {
            presentAlert(title: "PDF Export Failed", message: error.localizedDescription)
        }
        #else
        // iOS optional path can be added if needed
        #endif
    }

    private func safeFileName() -> String {
        let base = "\(student.fullName) - Progress Report"
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|\n\r")
        return base.components(separatedBy: invalid).joined(separator: " ")
    }

    #if os(macOS)
    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
    #endif
}

// MARK: - Debounced Saver
@MainActor
final class DebouncedSaver: ObservableObject {
    private var task: Task<Void, Never>? = nil

    func scheduleSave(context: ModelContext, delay: Duration = .milliseconds(550)) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: delay)
            try? context.save()
        }
    }

    func flushSave(context: ModelContext) {
        task?.cancel()
        task = nil
        do {
            try context.save()
        } catch {
            print("[ProgressReport] Save failed: \(error)")
        }
    }
}

// MARK: - Preview
#Preview {
    let student = Student(firstName: "Yosef", lastName: "Cohen", birthday: Date(), level: .lower)
    StudentProgressReportView(student: student)
        .modelContainer(for: [Student.self, StudentProgressReport.self], inMemory: true)
}

