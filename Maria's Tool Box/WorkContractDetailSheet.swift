import SwiftUI
import SwiftData
import Foundation

struct WorkContractDetailSheet: View {
    let contract: WorkContract
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator
    
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]
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

    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) }) }
    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }

    private var scheduleDates: WorkScheduleDates {
        WorkScheduleDateLogic.compute(for: contract, allPlanItems: planItems)
    }
    
    private var likelyNextLesson: Lesson? {
        guard let currentLessonID = UUID(uuidString: contract.lessonID) else { return nil }
        return NextLessonResolver.resolveNextLesson(from: currentLessonID, lessons: lessons)
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
        _planItems = Query(filter: #Predicate<WorkPlanItem> { $0.workID == contractID })
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
        try? modelContext.save()
        close()
    }

    private func close() { onDone?() ?? dismiss() }
    
    private func deleteContract() {
        modelContext.delete(contract)
        close()
    }

    private func addPlan() {
        let item = WorkPlanItem(workID: contract.id, scheduledDate: newPlanDate, reason: newPlanReason)
        modelContext.insert(item)
    }

    private func studentName() -> String {
        guard let sid = UUID(uuidString: contract.studentID), let s = studentsByID[sid] else { return "Student" }
        return s.firstName
    }

    private func lessonTitle() -> String {
        guard let lid = UUID(uuidString: contract.lessonID), let l = lessonsByID[lid] else { return "Lesson" }
        return l.name
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
