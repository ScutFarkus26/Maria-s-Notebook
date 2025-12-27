import SwiftUI
import SwiftData

struct StudentMeetingsTab: View {
    let student: Student

    // MARK: - Environment & Data
    @Environment(\.modelContext) private var modelContext

    // Query all work items; we'll filter by participant membership
    @Query(sort: [SortDescriptor(\WorkModel.createdAt, order: .reverse)])
    private var workItems: [WorkModel]

    // Query all meetings; we'll filter by studentID
    @Query(sort: [SortDescriptor(\StudentMeeting.date, order: .reverse)])
    private var meetingItemsRaw: [StudentMeeting]

    private var meetingItems: [StudentMeeting] { meetingItemsRaw.filter { $0.studentID == student.id } }

    // MARK: - Local State for current meeting (persisted via UserDefaults per student)
    @State private var isCompleted: Bool = false
    @State private var reflectionText: String = ""
    @State private var focusText: String = ""
    @State private var requestsText: String = ""
    @State private var guideNotesText: String = ""

    @State private var expandedHistoryIDs: Set<UUID> = []

    // Editing sheet state
    @State private var editingMeeting: StudentMeeting? = nil
    @State private var editDate: Date = Date()
    @State private var editCompleted: Bool = false
    @State private var editReflection: String = ""
    @State private var editFocus: String = ""
    @State private var editRequests: String = ""
    @State private var editGuideNotes: String = ""

    // Work snapshot settings
    @AppStorage("WorkAge.overdueDays") private var workOverdueDays: Int = 14

    private var todayString: String {
        DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
    }

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            currentMeetingSection
            activeWorkSnapshotSection
            historySection
            carryForwardSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            loadCurrentFromDefaults()
            migrateHistoryIfNeeded()
        }
        .onChange(of: isCompleted) { _, _ in saveCurrentToDefaults() }
        .onChange(of: reflectionText) { _, _ in saveCurrentToDefaults() }
        .onChange(of: focusText) { _, _ in saveCurrentToDefaults() }
        .onChange(of: requestsText) { _, _ in saveCurrentToDefaults() }
        .onChange(of: guideNotesText) { _, _ in saveCurrentToDefaults() }
        .sheet(item: $editingMeeting) { meeting in
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit Meeting").font(.headline)
                DatePicker("Date", selection: $editDate, displayedComponents: .date)
                Toggle("Completed", isOn: $editCompleted)
                TextField("Reflection", text: $editReflection, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                TextField("Focus", text: $editFocus, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                TextField("Requests", text: $editRequests, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                TextField("Guide notes", text: $editGuideNotes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                HStack {
                    Spacer()
                    Button("Cancel") { editingMeeting = nil }
                    Button("Save") {
                        meeting.date = editDate
                        meeting.completed = editCompleted
                        meeting.reflection = editReflection
                        meeting.focus = editFocus
                        meeting.requests = editRequests
                        meeting.guideNotes = editGuideNotes
                        try? modelContext.save()
                        editingMeeting = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
#if os(macOS)
            .frame(minWidth: 420)
#endif
        }
    }

    // MARK: - Sections

    private var currentMeetingSection: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2")
                        .foregroundStyle(.secondary)
                    Text("Weekly Meeting")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        saveCurrentToHistory()
                    } label: {
                        Label("Save to History", systemImage: "tray.and.arrow.down.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isCurrentEmpty)
                }

                HStack(alignment: .center) {
                    Label(todayString, systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Completed", isOn: $isCompleted)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    Text("Completed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                textArea(title: "Student reflection", text: $reflectionText, placeholder: "What went well? What was hard?")
                textArea(title: "Focus for this week", text: $focusText, placeholder: "1–3 priorities…")
                textArea(title: "Lesson requests", text: $requestsText, placeholder: "Lessons the student wants…")
                textArea(title: "Guide notes (private)", text: $guideNotesText, placeholder: "Observations only…")

                HStack {
                    Spacer()
                    Button("Clear") {
                        clearCurrent()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var activeWorkSnapshotSection: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Active Work Snapshot")
                    .font(.headline)
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 6) {
                    rowLine(label: "Open work", value: openWorkCountText)
                    if !openWorksForStudent.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(openWorksForStudent.prefix(3)) { work in
                                workRowLine(work)
                            }
                        }
                    }
                    rowLine(label: "Overdue/stuck", value: overdueWorkCountText)
                    if !overdueWorksForStudent.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(overdueWorksForStudent.prefix(3)) { work in
                                workRowLine(work)
                            }
                        }
                    }
                    rowLine(label: "Recently completed", value: recentlyCompletedCountText)
                    if !recentCompletedWorksForStudent.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(recentCompletedWorksForStudent.prefix(3)) { work in
                                workRowLine(work, showCompletedDate: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var historySection: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Meeting History")
                    .font(.headline)
                    .foregroundStyle(.primary)

                if meetingItems.isEmpty {
                    Text("No prior meetings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(meetingItems) { item in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedHistoryIDs.contains(item.id) },
                                    set: { new in
                                        if new { expandedHistoryIDs.insert(item.id) } else { expandedHistoryIDs.remove(item.id) }
                                    }
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 6) {
                                    historyDetailLine(title: "Reflection", text: item.reflection)
                                    historyDetailLine(title: "Focus", text: item.focus)
                                    historyDetailLine(title: "Requests", text: item.requests)
                                    if !item.guideNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        historyDetailLine(title: "Guide notes", text: item.guideNotes)
                                    }
                                }
                                .padding(.top, 4)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(Self.dateFormatter.string(from: item.date))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if item.completed { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                                    Text("•")
                                        .foregroundStyle(.secondary)
                                    Text(summary(for: item))
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Menu {
                                        Button("Edit", systemImage: "square.and.pencil") { beginEdit(item) }
                                        Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
                                    } label: {
                                        Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disclosureGroupStyle(.automatic)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }

    private var carryForwardSection: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                Text("Carry-forward")
                    .font(.headline)
                Text("Carry-forward suggestions (future): unfinished focus items from last week appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Work Snapshot Computations

    private var worksForStudent: [WorkModel] {
        workItems.filter { work in
            (work.participants ?? []).contains { $0.studentID == student.id }
        }
    }

    private var openWorksForStudent: [WorkModel] {
        worksForStudent.filter { work in
            (work.participants ?? []).contains { $0.studentID == student.id && $0.completedAt == nil }
        }
    }

    private var overdueWorksForStudent: [WorkModel] {
        let threshold = Calendar.current.date(byAdding: .day, value: -workOverdueDays, to: Date()) ?? Date.distantPast
        return worksForStudent.filter { work in
            let isOpenForStudent = (work.participants ?? []).contains { $0.studentID == student.id && $0.completedAt == nil }
            let isOld = work.createdAt < threshold
            return isOpenForStudent && isOld
        }
    }

    private var recentCompletedWorksForStudent: [WorkModel] {
        let threshold = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
        return worksForStudent.filter { work in
            (work.participants ?? []).contains { $0.studentID == student.id && ($0.completedAt ?? .distantPast) >= threshold }
        }
    }

    private var openWorkCountText: String { openWorksForStudent.isEmpty ? "—" : "\(openWorksForStudent.count)" }
    private var overdueWorkCountText: String { overdueWorksForStudent.isEmpty ? "—" : "\(overdueWorksForStudent.count)" }
    private var recentlyCompletedCountText: String { recentCompletedWorksForStudent.isEmpty ? "—" : "\(recentCompletedWorksForStudent.count)" }

    private func workRowLine(_ work: WorkModel, showCompletedDate: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.secondary)
            Text(workDisplayTitle(work))
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineLimit(1)
            if showCompletedDate, let date = (work.participants ?? []).first(where: { $0.studentID == student.id })?.completedAt {
                Text("•")
                    .foregroundStyle(.secondary)
                Text(Self.dateFormatter.string(from: date))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func workDisplayTitle(_ work: WorkModel) -> String {
        let trimmed = work.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return work.workType.rawValue
    }

    // MARK: - Persistence (UserDefaults for current, SwiftData for history)

    private var currentPrefix: String { "StudentMeetings.current." + student.id.uuidString }
    private var historyKey: String { "StudentMeetings.history." + student.id.uuidString }

    private var isCurrentEmpty: Bool {
        reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        focusText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        requestsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        guideNotesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadCurrentFromDefaults() {
        let d = UserDefaults.standard
        isCompleted = d.bool(forKey: currentPrefix + ".completed")
        reflectionText = d.string(forKey: currentPrefix + ".reflection") ?? ""
        focusText = d.string(forKey: currentPrefix + ".focus") ?? ""
        requestsText = d.string(forKey: currentPrefix + ".requests") ?? ""
        guideNotesText = d.string(forKey: currentPrefix + ".guideNotes") ?? ""
    }

    private func saveCurrentToDefaults() {
        let d = UserDefaults.standard
        d.set(isCompleted, forKey: currentPrefix + ".completed")
        d.set(reflectionText, forKey: currentPrefix + ".reflection")
        d.set(focusText, forKey: currentPrefix + ".focus")
        d.set(requestsText, forKey: currentPrefix + ".requests")
        d.set(guideNotesText, forKey: currentPrefix + ".guideNotes")
    }

    private func clearCurrent() {
        isCompleted = false
        reflectionText = ""
        focusText = ""
        requestsText = ""
        guideNotesText = ""
        saveCurrentToDefaults()
    }

    private func migrateHistoryIfNeeded() {
        // If we already have SwiftData meetings for this student, skip migration
        if !meetingItems.isEmpty { return }
        let d = UserDefaults.standard
        guard let data = d.data(forKey: historyKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([LegacyMeetingEntry].self, from: data)
            var inserted = 0
            for entry in decoded {
                let m = StudentMeeting(
                    studentID: student.id,
                    date: entry.date,
                    completed: entry.completed,
                    reflection: entry.reflection,
                    focus: entry.focus,
                    requests: entry.requests,
                    guideNotes: entry.guideNotes
                )
                modelContext.insert(m)
                inserted += 1
            }
            if inserted > 0 { try? modelContext.save() }
            d.removeObject(forKey: historyKey)
        } catch {
            // If decoding fails, leave defaults as-is
        }
    }

    private func saveCurrentToHistory() {
        let trimmedReflection = reflectionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFocus = focusText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRequests = requestsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGuide = guideNotesText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(trimmedReflection.isEmpty && trimmedFocus.isEmpty && trimmedRequests.isEmpty && trimmedGuide.isEmpty) else { return }
        let entry = StudentMeeting(
            studentID: student.id,
            date: Date(),
            completed: isCompleted,
            reflection: trimmedReflection,
            focus: trimmedFocus,
            requests: trimmedRequests,
            guideNotes: trimmedGuide
        )
        modelContext.insert(entry)
        try? modelContext.save()
        clearCurrent()
    }

    private func beginEdit(_ item: StudentMeeting) {
        editDate = item.date
        editCompleted = item.completed
        editReflection = item.reflection
        editFocus = item.focus
        editRequests = item.requests
        editGuideNotes = item.guideNotes
        editingMeeting = item
    }

    private func delete(_ item: StudentMeeting) {
        modelContext.delete(item)
        try? modelContext.save()
    }

    // MARK: - UI Helpers

    private func rowLine(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text("\(label):")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    private func textArea(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .font(.body)
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08))
                    )
                if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    private func historyDetailLine(title: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(title):")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
                .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        )
    }

    // MARK: - Types & Formatters

    private struct LegacyMeetingEntry: Identifiable, Codable {
        let id: UUID
        let date: Date
        let completed: Bool
        let reflection: String
        let focus: String
        let requests: String
        let guideNotes: String
    }

    private func summary(for item: StudentMeeting) -> String {
        let focusTrim = item.focus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !focusTrim.isEmpty { return focusTrim }
        let reflTrim = item.reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reflTrim.isEmpty { return reflTrim }
        let reqTrim = item.requests.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reqTrim.isEmpty { return reqTrim }
        return "Meeting"
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()
}

#Preview {
    let container = ModelContainer.preview
    let context = container.mainContext
    let student = Student(firstName: "Alan", lastName: "Turing", birthday: Date(timeIntervalSince1970: 0), level: .upper)
    context.insert(student)
    return StudentMeetingsTab(student: student)
        .previewEnvironment(using: container)
        .padding()
}
