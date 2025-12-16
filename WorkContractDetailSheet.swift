import SwiftUI
import SwiftData

struct WorkContractDetailSheet: View {
    let contract: WorkContract
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Environment(\.calendar) private var calendar
    @EnvironmentObject private var saveCoordinator: SaveCoordinator
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]

    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) }) }
    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }

    @State private var status: WorkStatus
    @State private var hasSchedule: Bool
    @State private var scheduledDate: Date
    @State private var showScheduleSheet: Bool = false
    @State private var showPlannedBanner: Bool = false

    init(contract: WorkContract, onDone: (() -> Void)? = nil) {
        self.contract = contract
        self.onDone = onDone
        _status = State(initialValue: contract.status)
        let d = contract.scheduledDate ?? Date()
        _hasSchedule = State(initialValue: contract.scheduledDate != nil)
        _scheduledDate = State(initialValue: d)
    }

    private func lessonTitle() -> String {
        if let lid = UUID(uuidString: contract.lessonID), let l = lessonsByID[lid] {
            let t = l.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return "Lesson"
    }
    private func studentName() -> String {
        if let sid = UUID(uuidString: contract.studentID), let s = studentsByID[sid] {
            return StudentFormatter.displayName(for: s)
        }
        return "Student"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lessonTitle())
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(studentName())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    status = .complete
                    hasSchedule = false
                    contract.status = .complete
                    contract.completedAt = Date()
                    contract.scheduledDate = nil
                    try? modelContext.save()
                    close()
                } label: {
                    Label("Mark Complete", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
            }

            Picker("Status", selection: $status) {
                ForEach(WorkStatus.allCases, id: \.self) { s in
                    Text(label(for: s)).tag(s)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Schedule", isOn: $hasSchedule)
            if hasSchedule {
                DatePicker("Date", selection: $scheduledDate, displayedComponents: .date)
            }

            Divider().padding(.top, 4)

            // Schedule Next Lesson action
            Button {
                showScheduleSheet = true
            } label: {
                Label("Schedule Next Lesson…", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.bordered)

            HStack {
                Spacer()
                Button("Cancel") { close() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    #if os(macOS)
        .frame(minWidth: 360)
        .presentationSizing(.fitted)
    #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    #endif
        .sheet(isPresented: $showScheduleSheet) {
            ScheduleNextLessonSheet(contract: contract) {
                // On created: show a brief confirmation
                showPlannedBanner = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showPlannedBanner = false
                }
            }
        }
        .overlay(alignment: .top) {
            if showPlannedBanner {
                Text("Next lesson scheduled")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.green.opacity(0.95))
                    )
                    .foregroundColor(.white)
                    .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                    .padding(.top, 8)
            }
        }
    }

    private func label(for s: WorkStatus) -> String {
        switch s {
        case .active: return "Active"
        case .review: return "Review"
        case .complete: return "Complete"
        }
    }

    private func close() {
        if let onDone { onDone() } else { dismiss() }
    }

    private func save() {
        contract.status = status
        contract.scheduledDate = hasSchedule ? AppCalendar.startOfDay(scheduledDate) : nil
        if status == .complete {
            contract.completedAt = Date()
        } else {
            contract.completedAt = nil
        }
        try? modelContext.save()
        close()
    }
}

#Preview {
    let schema = AppSchema.schema
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: configuration)
    let ctx = container.mainContext

    let student = Student(firstName: "Ada", lastName: "Lovelace", birthday: Date(), level: .upper)
    let lesson = Lesson(name: "Long Division", subject: "Math", group: "Operations", subheading: "", writeUp: "")
    ctx.insert(student); ctx.insert(lesson)
    let c = WorkContract(studentID: student.id.uuidString, lessonID: lesson.id.uuidString, status: .active, scheduledDate: Date())
    ctx.insert(c)
    return WorkContractDetailSheet(contract: c)
        .previewEnvironment(using: container)
}

private struct NextLessonResolver {
    static func resolveNextLessonID(from contract: WorkContract, lessons: [Lesson]) -> UUID? {
        guard let currentID = UUID(uuidString: contract.lessonID),
              let current = lessons.first(where: { $0.id == currentID }) else {
            #if DEBUG
            print("[NextLessonResolver] Could not locate current lesson for contract: \(contract.lessonID)")
            #endif
            return nil
        }

        #if DEBUG
        print("[NextLessonResolver] Current lesson: \(current.id) – \(current.name)")
        #endif

        // Attempt explicit link (not present in this model). Fallback to collection ordering.
        let currentSubject = current.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentGroup = current.group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentSubject.isEmpty, !currentGroup.isEmpty else {
            #if DEBUG
            print("[NextLessonResolver] Missing subject/group; cannot resolve next lesson.")
            #endif
            return nil
        }

        let candidates = lessons.filter { l in
            l.subject.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentSubject) == .orderedSame &&
            l.group.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentGroup) == .orderedSame
        }
        .sorted { $0.orderInGroup < $1.orderInGroup }

        if let idx = candidates.firstIndex(where: { $0.id == current.id }), idx + 1 < candidates.count {
            let next = candidates[idx + 1]
            #if DEBUG
            print("[NextLessonResolver] Next lesson resolved: \(next.id) – \(next.name)")
            #endif
            return next.id
        } else {
            #if DEBUG
            print("[NextLessonResolver] No next lesson found in sequence.")
            #endif
            return nil
        }
    }
}

struct ScheduleNextLessonSheet: View {
    let contract: WorkContract
    var onCreated: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @Query(sort: \Lesson.name) private var lessons: [Lesson]
    @Query(sort: \Student.firstName) private var studentsAll: [Student]

    @State private var search: String = ""
    @State private var selectedLessonID: UUID? = nil
    @State private var showLessonPicker: Bool = true
    @State private var scheduleEnabled: Bool = false
    @State private var scheduleDate: Date = Date()
    @State private var notes: String = ""

    private var selectedLesson: Lesson? {
        guard let id = selectedLessonID else { return nil }
        return lessons.first(where: { $0.id == id })
    }

    private var filteredLessons: [Lesson] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if term.isEmpty { return lessons }
        return lessons.filter { l in
            let name = l.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = l.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            let group = l.group.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.localizedCaseInsensitiveContains(term) || subject.localizedCaseInsensitiveContains(term) || group.localizedCaseInsensitiveContains(term)
        }
    }

    init(contract: WorkContract, onCreated: (() -> Void)? = nil) {
        self.contract = contract
        self.onCreated = onCreated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schedule Next Lesson")
                .font(.title2)
                .fontWeight(.semibold)

            // Auto-selected lesson (if any)
            if let selected = selectedLesson {
                HStack(alignment: .center, spacing: 12) {
                    LessonRow(lesson: selected,
                              subtitle: lessonSubtitle(selected),
                              isSelected: true)
                    Spacer()
                    Button("Change…") { withAnimation { showLessonPicker = true } }
                }
            } else {
                Text("Select a lesson")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            // Lesson picker
            if showLessonPicker || selectedLesson == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose Lesson")
                        .font(.headline)
                    TextField("Search lessons…", text: $search)
                        .textFieldStyle(.roundedBorder)
                    List {
                        ForEach(filteredLessons) { lesson in
                            Button {
                                selectedLessonID = lesson.id
                                showLessonPicker = false
                            } label: {
                                LessonRow(lesson: lesson,
                                          subtitle: lessonSubtitle(lesson),
                                          isSelected: selectedLessonID == lesson.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(minHeight: 200)
                }
            }

            // Optional schedule + notes
            Toggle("Schedule on a date", isOn: $scheduleEnabled)
            if scheduleEnabled {
                DatePicker("Date", selection: $scheduleDate, displayedComponents: .date)
            }
            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedLessonID == nil)
            }
        }
        .padding(16)
    #if os(macOS)
        .frame(minWidth: 480)
        .presentationSizing(.fitted)
    #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    #endif
        .onAppear { autoSelectNextLessonIfPossible() }
    }

    private func lessonSubtitle(_ lesson: Lesson) -> String? {
        let subject = lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = lesson.group.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [subject, group].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func autoSelectNextLessonIfPossible() {
        if let nextID = NextLessonResolver.resolveNextLessonID(from: contract, lessons: lessons) {
            selectedLessonID = nextID
            showLessonPicker = false
        } else {
            showLessonPicker = true
        }
    }

    private func create() {
        guard let lessonID = selectedLessonID else { return }
        guard let sid = UUID(uuidString: contract.studentID) else { return }

        // Prevent duplicates: same lesson + same single student + not given
        // Unscheduled de-dupes against unscheduled; scheduled de-dupes against the same scheduled day (startOfDay)
        if scheduleEnabled {
            let day = AppCalendar.startOfDay(scheduleDate)
            let fetch = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lessonID && $0.givenAt == nil && $0.scheduledFor == day })
            let existing = (try? modelContext.fetch(fetch)) ?? []
            if existing.contains(where: { Set($0.studentIDs) == Set([sid]) }) {
                dismiss()
                return
            }
        } else {
            let fetch = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.lessonID == lessonID && $0.givenAt == nil && $0.scheduledFor == nil })
            let existing = (try? modelContext.fetch(fetch)) ?? []
            if existing.contains(where: { Set($0.studentIDs) == Set([sid]) }) {
                dismiss()
                return
            }
        }

        let newSL = StudentLesson(
            id: UUID(),
            lessonID: lessonID,
            studentIDs: [sid],
            createdAt: Date(),
            scheduledFor: nil,
            givenAt: nil,
            isPresented: false,
            notes: notes,
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )

        // Set relationships
        let lessonFetch = FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == lessonID })
        let studentFetch = FetchDescriptor<Student>(predicate: #Predicate { $0.id == sid })
        newSL.lesson = (try? modelContext.fetch(lessonFetch))?.first
        if let s = (try? modelContext.fetch(studentFetch))?.first { newSL.students = [s] }

        if scheduleEnabled {
            let normalized = AppCalendar.startOfDay(scheduleDate)
            newSL.setScheduledFor(normalized, using: AppCalendar.shared)
        }

        modelContext.insert(newSL)
        _ = saveCoordinator.save(modelContext, reason: "Schedule next lesson from WorkContract")
        onCreated?()
        dismiss()
    }
}

private struct LessonRow: View {
    let lesson: Lesson
    let subtitle: String?
    let isSelected: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.name)
                    .font(.body.weight(.medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
    }
}

