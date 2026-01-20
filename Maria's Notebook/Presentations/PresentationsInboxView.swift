// PresentationsInboxView.swift
// Inbox section extracted from PresentationsView

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PresentationsInboxView: View {
    let readyLessons: [StudentLesson]
    let blockedLessons: [StudentLesson]
    let getBlockingWork: (StudentLesson) -> [UUID: WorkModel]
    let filteredSnapshot: (StudentLesson) -> StudentLessonSnapshot
    let missWindow: PresentationsMissWindow
    @Binding var missWindowRaw: String
    @Binding var selectedStudentLessonForDetail: StudentLesson?
    @Binding var isInboxTargeted: Bool
    @Binding var isCalendarMinimized: Bool
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    
    @Query private var studentLessons: [StudentLesson]
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]
    
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    
    // Default sorting is by age
    private let sortMode: PresentationsSortMode = .age

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "tray")
                        .imageScale(.large)
                        .foregroundStyle(Color.accentColor)
                    Text("Presentations")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    
                    #if os(iOS)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isCalendarMinimized.toggle()
                        }
                    } label: {
                        Image(systemName: isCalendarMinimized ? "calendar" : "calendar.badge.minus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(Color.primary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    #endif
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search students or lessons", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            searchDebounceTask?.cancel()
                            debouncedSearchText = searchText
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .onChange(of: searchText) { _, newValue in
                    searchDebounceTask?.cancel()
                    searchDebounceTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000) // 250ms debounce
                        guard !Task.isCancelled else { return }
                        debouncedSearchText = newValue
                    }
                }
            }
            .padding(.bottom, 8)
            .background(.regularMaterial)
            
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    // 1. BLOCKED / WAITING SECTION
                    if !filteredAndSortedBlockedLessons.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("On Deck (Waiting for Work)", systemImage: "hourglass")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(filteredAndSortedBlockedLessons, id: \.id) { sl in
                                        inboxRow(sl, blockingWork: getBlockingWork(sl))
                                    }
                                }
                                .padding(.horizontal, 12)
                            }
                        }
                        .padding(.top, 12)
                    }

                    // 2. READY SECTION
                    if filteredAndSortedReadyLessons.isEmpty {
                        if filteredAndSortedBlockedLessons.isEmpty {
                            ContentUnavailableView("All Caught Up", systemImage: "checkmark.circle", description: Text("No unscheduled presentations."))
                                .padding(.top, 40)
                        } else {
                            Text("All planned presentations are waiting on work.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 20)
                        }
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ], alignment: .leading, spacing: 8) {
                            ForEach(filteredAndSortedReadyLessons, id: \.id) { sl in
                                inboxRow(sl)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .overlay {
            if isInboxTargeted {
                Color.accentColor.opacity(0.15)
                    .allowsHitTesting(false)
                
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(2)
                    .allowsHitTesting(false)
                
                VStack {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(Color.accentColor)
                    Text("Drop to Unschedule")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
                .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.text], delegate: InboxDropDelegate(
            modelContext: modelContext,
            studentLessons: studentLessons,
            isTargeted: $isInboxTargeted
        ))
    }
    
    // MARK: - Filtering and Sorting
    
    private var lessonsByID: [UUID: Lesson] {
        Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
    }
    
    private var studentsByID: [UUID: Student] {
        Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
    }
    
    private func lessonTitle(for sl: StudentLesson) -> String {
        if let lessonID = UUID(uuidString: sl.lessonID), let lesson = lessonsByID[lessonID] {
            let name = lesson.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        return "Lesson \(String(sl.lessonID.prefix(6)))"
    }
    
    private func studentNames(for sl: StudentLesson) -> String {
        let snapshot = filteredSnapshot(sl)
        let names = snapshot.studentIDs.compactMap { id -> String? in
            guard let student = studentsByID[id] else { return nil }
            return StudentFormatter.displayName(for: student)
        }
        return names.joined(separator: ", ")
    }
    
    private func matchesSearch(_ sl: StudentLesson) -> Bool {
        guard !debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        let query = debouncedSearchText.lowercased()
        let lessonTitleLower = lessonTitle(for: sl).lowercased()
        let studentNamesLower = studentNames(for: sl).lowercased()
        return lessonTitleLower.contains(query) || studentNamesLower.contains(query)
    }
    
    private func sortedLessons(_ lessons: [StudentLesson]) -> [StudentLesson] {
        let matched = lessons.filter { matchesSearch($0) }
        
        switch sortMode {
        case .lesson:
            return matched.sorted { lessonTitle(for: $0).localizedCaseInsensitiveCompare(lessonTitle(for: $1)) == .orderedAscending }
        case .student:
            return matched.sorted { studentNames(for: $0).localizedCaseInsensitiveCompare(studentNames(for: $1)) == .orderedAscending }
        case .age:
            // Sort by creation date (older first)
            return matched.sorted { $0.createdAt < $1.createdAt }
        case .needsAttention:
            // Sort by creation date (older first, as older lessons need more attention)
            return matched.sorted { $0.createdAt < $1.createdAt }
        }
    }
    
    private var filteredAndSortedReadyLessons: [StudentLesson] {
        sortedLessons(readyLessons)
    }
    
    private var filteredAndSortedBlockedLessons: [StudentLesson] {
        sortedLessons(blockedLessons)
    }

    @ViewBuilder
    private func inboxRow(_ sl: StudentLesson, blockingWork: [UUID: WorkModel] = [:]) -> some View {
        HStack(spacing: 0) {
            StudentLessonPill(
                snapshot: filteredSnapshot(sl),
                day: Date(),
                targetStudentLessonID: sl.id,
                enableMissHighlight: true,
                blockingWork: blockingWork
            )
            .onTapGesture { selectedStudentLessonForDetail = sl }
            .onDrag {
                let provider = NSItemProvider(object: NSString(string: sl.id.uuidString))
                provider.suggestedName = sl.lesson?.name ?? "Lesson"
                return provider
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

// MARK: - Drop Delegate for Inbox
private struct InboxDropDelegate: DropDelegate {
    let modelContext: ModelContext
    let studentLessons: [StudentLesson]
    @Binding var isTargeted: Bool
    
    func dropEntered(info: DropInfo) {
        withAnimation { isTargeted = true }
    }
    
    func dropExited(info: DropInfo) {
        withAnimation { isTargeted = false }
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }
    
    func performDrop(info: DropInfo) -> Bool {
        withAnimation { isTargeted = false }
        let providers = info.itemProviders(for: [.text])
        guard let provider = providers.first else { return false }
        
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let str = reading as? String, let id = UUID(uuidString: str) else { return }
            
            Task { @MainActor in
                if let sl = studentLessons.first(where: { $0.id == id }) {
                    // Only process if it actually has a schedule to clear
                    if sl.scheduledFor != nil {
                        sl.scheduledFor = nil
                        #if DEBUG
                        sl.checkInboxInvariant()
                        #endif
                        do {
                            try modelContext.save()
                        } catch {
                            #if DEBUG
                            print("Presentations inbox unschedule save failed: \(error)")
                            #endif
                        }
                    }
                }
            }
        }
        return true
    }
}

