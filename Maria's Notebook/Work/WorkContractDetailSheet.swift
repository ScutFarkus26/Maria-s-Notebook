import SwiftUI
import SwiftData
import Foundation
#if DEBUG
#endif

struct WorkContractDetailSheet: View {
    let contract: WorkContract
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator
    
    // OPTIMIZATION: Load only related lessons and students instead of all
    @State private var relatedLesson: Lesson? = nil
    @State private var relatedLessons: [Lesson] = [] // For NextLessonResolver - same subject/group
    @State private var relatedStudent: Student? = nil
    
    @Query private var workNotes: [ScopedNote]
    @Query private var presentations: [Presentation]
    @Query private var planItems: [WorkPlanItem]
    @Query private var peerContracts: [WorkContract]
    
    @State private var resolvedPresentationID: UUID? = nil
    @State private var presentationNotes: [ScopedNote] = []
    @State private var showPresentationNotes: Bool = true
    @State private var showAddNoteSheet: Bool = false
    @State private var newNoteText: String = ""
    @State private var showScheduleSheet: Bool = false
    @State private var showPlannedBanner: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var isRestoringData: Bool = false

    @State private var status: WorkStatus
    @State private var workKind: WorkKind
    @State private var workTitle: String = ""
    @State private var completionOutcome: CompletionOutcome? = nil
    @State private var completionNote: String = ""
    
    @State private var newPlanDate: Date = Date()
    @State private var newPlanReason: WorkPlanItem.Reason = .progressCheck
    @State private var newPlanNote: String = ""

    private var scheduleDates: WorkScheduleDates {
        WorkScheduleDateLogic.compute(for: contract, allPlanItems: planItems)
    }
    
    private var likelyNextLesson: Lesson? {
        guard let currentLessonID = UUID(uuidString: contract.lessonID),
              relatedLessons.first(where: { $0.id == currentLessonID }) != nil else { return nil }
        return NextLessonResolver.resolveNextLesson(from: currentLessonID, lessons: relatedLessons)
    }

    init(contract: WorkContract, onDone: (() -> Void)? = nil) {
        self.contract = contract
        self.onDone = onDone
        _status = State(initialValue: contract.status)
        _workTitle = State(initialValue: contract.title ?? "")
        _completionOutcome = State(initialValue: contract.completionOutcome)
        _completionNote = State(initialValue: contract.completionNote ?? "")
        _workKind = State(initialValue: contract.kind ?? .practiceLesson)
        
        let contractID = contract.id
        let workID = contractID.uuidString
        _workNotes = Query(filter: #Predicate<ScopedNote> { $0.workContractID == workID })
        // CloudKit compatibility: workID is now String, so use workID string
        _planItems = Query(filter: #Predicate<WorkPlanItem> { $0.workID == workID })
        let lessonID = contract.lessonID
        _peerContracts = Query(filter: #Predicate<WorkContract> { $0.lessonID == lessonID })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection()
                    Divider()
                    if status == .complete { completionSection(); Divider() }
                    calendarSection()
                    Divider()
                    notesSection()
                    
                    Button(role: .destructive) { showDeleteAlert = true } label: {
                        Label("Delete Work", systemImage: "trash")
                    }.frame(maxWidth: .infinity).padding(.top, 20)
                }.padding(24)
            }
            Divider()
            HStack {
                Button("Cancel") { close() }
                Spacer()
                Button("Save") { save() }.buttonStyle(.borderedProminent)
            }.padding(16).background(.bar)
        }
        .onAppear {
            loadRelatedData()
            #if DEBUG
            PerformanceLogger.logScreenLoad(
                screenName: "WorkContractDetailSheet",
                itemCounts: [
                    "lessons": relatedLessons.count,
                    "students": relatedStudent != nil ? 1 : 0,
                    "workNotes": workNotes.count,
                    "presentations": presentations.count,
                    "planItems": planItems.count,
                    "peerContracts": peerContracts.count
                ]
            )
            #endif
            resolvedPresentationID = resolvePresentationID()
            reloadPresentationNotes()
        }
        .sheet(isPresented: $showScheduleSheet) {
            ScheduleNextLessonSheet(contract: contract) { showPlannedBanner = true }
        }
        .alert("Delete?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { deleteContract() }
        }
    }

    @ViewBuilder
    private func headerSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(studentName()).font(.system(size: 34, weight: .bold, design: .rounded))
            TextField("Work Title", text: $workTitle).font(.title2).padding(8).background(Color.primary.opacity(0.05)).cornerRadius(8)
            
            HStack {
                Label(lessonTitle(), systemImage: "book.closed").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Picker("Kind", selection: $workKind) {
                    Text("Practice").tag(WorkKind.practiceLesson)
                    Text("Follow-Up").tag(WorkKind.followUpAssignment)
                    Text("Project").tag(WorkKind.research)
                }.labelsHidden().controlSize(.small)
            }

            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    statusBtn(.active, "Active"); statusBtn(.review, "Review"); statusBtn(.complete, "Complete")
                }.background(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
                
                if status != .complete, likelyNextLesson != nil {
                    Button { showScheduleSheet = true } label: {
                        Image(systemName: "lock.open.fill").padding(8).background(Color.accentColor.opacity(0.1)).cornerRadius(8)
                    }
                }
            }
        }
    }

    @ViewBuilder private func statusBtn(_ s: WorkStatus, _ label: String) -> some View {
        Button(label) { status = s }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(status == s ? Color.accentColor.opacity(0.1) : Color.clear)
            .foregroundStyle(status == s ? Color.accentColor : .primary)
    }

    @ViewBuilder private func completionSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Outcome", selection: $completionOutcome) {
                Text("Select...").tag(nil as CompletionOutcome?)
                ForEach(CompletionOutcome.allCases, id: \.self) { Text(labelForOutcome($0)).tag($0 as CompletionOutcome?) }
            }
            TextField("Notes", text: $completionNote).textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder private func calendarSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendar").font(.headline)
            HStack {
                DatePicker("", selection: $newPlanDate, displayedComponents: .date).labelsHidden()
                Button("Add") { addPlan() }.buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder private func notesSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Notes").font(.headline); Spacer(); Button("+") { showAddNoteSheet = true } }
            ForEach(workNotes) { note in
                VStack(alignment: .leading) {
                    Text(note.body).font(.body)
                    Text(note.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
                }.padding(8).background(Color.primary.opacity(0.04)).cornerRadius(8)
            }
        }
    }

    private func save() {
        contract.status = status
        contract.title = workTitle
        contract.kind = workKind
        contract.completionOutcome = completionOutcome
        contract.completionNote = completionNote
        saveCoordinator.save(modelContext, reason: "Saving work contract")
        close()
    }

    private func close() { onDone?() ?? dismiss() }
    
    private func deleteContract() {
        modelContext.delete(contract)
        saveCoordinator.save(modelContext, reason: "Deleting work contract")
        close()
    }

    private func addPlan() {
        let item = WorkPlanItem(workID: contract.id, scheduledDate: newPlanDate, reason: newPlanReason)
        modelContext.insert(item)
        saveCoordinator.save(modelContext, reason: "Adding plan item")
    }

    /// OPTIMIZATION: Load only related lessons and students on demand
    private func loadRelatedData() {
        // Load the specific lesson
        if let lessonID = UUID(uuidString: contract.lessonID) {
            let lessonDescriptor = FetchDescriptor<Lesson>(
                predicate: #Predicate<Lesson> { $0.id == lessonID }
            )
            relatedLesson = modelContext.safeFetchFirst(lessonDescriptor)
            
            // If we found the lesson, load lessons in the same subject/group for NextLessonResolver
            if let lesson = relatedLesson {
                let subject = lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
                let group = lesson.group.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !subject.isEmpty, !group.isEmpty else { return }
                
                // Load all lessons and filter in memory (predicates don't support trimmingCharacters or caseInsensitiveCompare)
                let allLessonsDescriptor = FetchDescriptor<Lesson>(
                    sortBy: [SortDescriptor(\.orderInGroup)]
                )
                let allLessons = modelContext.safeFetch(allLessonsDescriptor)
                relatedLessons = allLessons.filter { l in
                    let lSubject = l.subject.trimmingCharacters(in: .whitespacesAndNewlines)
                    let lGroup = l.group.trimmingCharacters(in: .whitespacesAndNewlines)
                    return lSubject.caseInsensitiveCompare(subject) == .orderedSame &&
                           lGroup.caseInsensitiveCompare(group) == .orderedSame
                }
            }
        }
        
        // Load the specific student
        if let studentID = UUID(uuidString: contract.studentID) {
            let studentDescriptor = FetchDescriptor<Student>(
                predicate: #Predicate<Student> { $0.id == studentID }
            )
            relatedStudent = modelContext.safeFetchFirst(studentDescriptor)
        }
    }
    
    private func studentName() -> String {
        return relatedStudent?.firstName ?? "Student"
    }

    private func lessonTitle() -> String {
        return relatedLesson?.name ?? "Lesson"
    }

    private func resolvePresentationID() -> UUID? {
        guard let pid = contract.presentationID else { return nil }
        return UUID(uuidString: pid)
    }

    private func reloadPresentationNotes() { /* Logic for ScopedNotes */ }

    private func labelForOutcome(_ o: CompletionOutcome) -> String {
        switch o {
        case .mastered: return "Mastered"
        case .needsMorePractice: return "Keep Practicing"
        default: return o.rawValue.capitalized
        }
    }
}

// MARK: - Helpers
private struct NextLessonResolver {
    static func resolveNextLesson(from currentID: UUID, lessons: [Lesson]) -> Lesson? {
        guard let current = lessons.first(where: { $0.id == currentID }) else { return nil }
        let candidates = lessons.filter { $0.subject == current.subject && $0.group == current.group }
            .sorted { $0.orderInGroup < $1.orderInGroup }
        if let idx = candidates.firstIndex(where: { $0.id == current.id }), idx + 1 < candidates.count {
            return candidates[idx + 1]
        }
        return nil
    }
}

struct ScheduleNextLessonSheet: View {
    let contract: WorkContract
    var onCreated: () -> Void
    @Environment(\.dismiss) var dismiss
    var body: some View {
        Button("Tap to Unlock") { onCreated(); dismiss() }.padding()
    }
}
