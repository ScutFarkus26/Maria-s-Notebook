import SwiftUI
import CoreData

struct OpenWorkListView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // OPTIMIZATION: Query only open works at database level instead of loading all and filtering in memory
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: false)],
        predicate: NSPredicate(format: "statusRaw != %@", "complete")
    ) private var openWorks: FetchedResults<CDWorkModel>

    @FetchRequest(sortDescriptors: []) private var lessons: FetchedResults<CDLesson>
    @FetchRequest(sortDescriptors: []) private var lessonAssignments: FetchedResults<CDLessonAssignment>

    @State private var selectedWork: CDWorkModel?

    // Pagination state
    @State private var pagination = PaginationState(pageSize: 50)

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    private var lessonsByID: [UUID: CDLesson] {
        Dictionary(
            lessons.compactMap { lesson -> (UUID, CDLesson)? in
                guard let id = lesson.id else { return nil }
                return (id, lesson)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var lessonAssignmentsByID: [UUID: CDLessonAssignment] {
        Dictionary(
            lessonAssignments.compactMap { la -> (UUID, CDLessonAssignment)? in
                guard let id = la.id else { return nil }
                return (id, la)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Paginated open works for display
    private var displayedWorks: [CDWorkModel] {
        Array(openWorks).paginated(using: pagination)
    }

    private func linkedLessonAssignment(for work: CDWorkModel) -> CDLessonAssignment? {
        guard let idString = work.presentationID,
              let id = UUID(uuidString: idString) else { return nil }
        return lessonAssignmentsByID[id]
    }

    private func linkedLesson(for work: CDWorkModel) -> CDLesson? {
        // Priority 1: Try CDWorkModel.lessonID directly (most reliable)
        if !work.lessonID.isEmpty, let lessonID = UUID(uuidString: work.lessonID) {
            if let lesson = lessonsByID[lessonID] {
                return lesson
            }
        }
        
        // Priority 2: Try through CDLessonAssignment relationship
        if let la = linkedLessonAssignment(for: work) {
            // Use lesson relationship if available
            if let lesson = la.lesson {
                return lesson
            }
            
            // Fallback: Convert CDLessonAssignment.lessonID to UUID for lookup
            if let lessonIDUUID = la.lessonIDUUID {
                return lessonsByID[lessonIDUUID]
            }
        }
        
        return nil
    }

    private func workTitle(_ work: CDWorkModel) -> String {
        let title = work.title.trimmed()
        if !title.isEmpty { return title }
        
        // Use kind for type label
        let typeLabel = (work.kind ?? .research).displayName
        
        if let lesson = linkedLesson(for: work) { return "\(typeLabel): \(lesson.name)" }
        return typeLabel
    }

    private func workSubtitle(_ work: CDWorkModel) -> String {
        let date: Date = {
            if let la = linkedLessonAssignment(for: work) {
                return la.presentedAt ?? la.scheduledFor ?? la.createdAt ?? .distantPast
            }
            return work.createdAt ?? .distantPast
        }()
        let dateString = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        if let lesson = linkedLesson(for: work) {
            let subject = lesson.subject.trimmed()
            return subject.isEmpty ? dateString : "\(subject) • \(dateString)"
        }
        return dateString
    }

    @ViewBuilder
    private func workDetailSheetContent(for work: CDWorkModel) -> some View {
        WorkDetailView(workID: work.id ?? UUID(), onDone: {
            selectedWork = nil
        })
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 640)
        .presentationSizingFitted()
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(displayedWorks) { work in
                    let participants = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
                    let openCount = participants.filter { $0.completedAt == nil }.count
                    let title = workTitle(work)
                    let subtitle = workSubtitle(work)
                    let badge: WorkCardBadge? = openCount > 0 ? .openCount(openCount) : nil
                    WorkCard.list(
                        work: work,
                        title: title,
                        subtitle: subtitle,
                        badge: badge,
                        onOpen: { w in selectedWork = w }
                    )
                }

                // Pagination footer
                if pagination.totalCount > 0 {
                    Section {
                        PaginatedListFooter(state: pagination, itemName: "open works")
                    }
                }
            }
            .navigationTitle("Open Work")
            .onChange(of: openWorks.count) { _, newCount in
                pagination.updateTotal(newCount)
            }
            .onAppear {
                pagination.updateTotal(openWorks.count)
            }
        }
        // Fix: Use 'isPresented' to avoid ambiguity between standard
        // 'sheet(item:)' and 'SheetPresentationHelpers' extension
        .sheet(isPresented: Binding(
            get: { selectedWork != nil },
            set: { if !$0 { selectedWork = nil } }
        )) {
            if let work = selectedWork {
                workDetailSheetContent(for: work)
            }
        }
    }
}

#Preview {
    Text("OpenWorkListView requires live data")
}
