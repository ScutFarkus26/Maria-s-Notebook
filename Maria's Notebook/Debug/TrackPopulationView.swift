#if DEBUG
import SwiftUI
import SwiftData

/// Debug tool to populate the "Tracks" view from existing data.
/// Scans lessons, presentations, and work contracts to identify potential group tracks.
struct TrackPopulationView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var potentialTracks: [PotentialTrack] = []
    @State private var isScanning: Bool = false
    @State private var isImporting: Bool = false
    @State private var importProgress: (current: Int, total: Int, currentTrack: String) = (0, 0, "")
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Track Population Tool")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: scanForTracks) {
                    Label("Scan", systemImage: "magnifyingglass")
                }
                .disabled(isScanning)
            }
            .padding()
            
            Divider()
            
            // Content
            if isScanning {
                ProgressView("Scanning for potential tracks...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else if isImporting {
                VStack(spacing: 16) {
                    ProgressView(value: Double(importProgress.current), total: Double(importProgress.total)) {
                        Text("Importing tracks...")
                            .font(.headline)
                    }
                    Text("\(importProgress.current) of \(importProgress.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !importProgress.currentTrack.isEmpty {
                        Text("Processing: \(importProgress.currentTrack)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if potentialTracks.isEmpty {
                ContentUnavailableView(
                    "No Tracks Found",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Click 'Scan' to search for potential tracks from your existing data.")
                )
            } else {
                // Selection controls
                HStack {
                    Button(action: selectAll) {
                        Text("Select All")
                    }
                    Button(action: deselectAll) {
                        Text("Deselect All")
                    }
                    Spacer()
                    Text("\(selectedCount) selected")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Track list
                List {
                    ForEach($potentialTracks) { $track in
                        TrackRow(track: $track)
                    }
                }
                .listStyle(.plain)
                
                // Import button
                Divider()
                HStack {
                    Spacer()
                    Button(action: importSelectedTracks) {
                        Label("Import \(selectedCount) Tracks", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCount == 0 || isImporting)
                }
                .padding()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var selectedCount: Int {
        potentialTracks.filter { $0.isSelected }.count
    }
    
    // MARK: - Actions
    
    private func scanForTracks() {
        isScanning = true
        potentialTracks = []
        
        Task { @MainActor in
            // Fetch all data on main actor (required for ModelContext)
            let lessons: [Lesson]
            let presentations: [Presentation]
            let workModels: [WorkModel]
            
            do {
                lessons = try modelContext.fetch(FetchDescriptor<Lesson>())
                presentations = try modelContext.fetch(FetchDescriptor<Presentation>())
                workModels = try modelContext.fetch(FetchDescriptor<WorkModel>())
            } catch {
                print("Error fetching data: \(error)")
                isScanning = false
                return
            }
            
            // Process data in background
            let tracks = await Task.detached {
                performScan(lessons: lessons, presentations: presentations, workModels: workModels)
            }.value
            
            potentialTracks = tracks
            isScanning = false
        }
    }
    
    nonisolated private func performScan(lessons: [Lesson], presentations: [Presentation], workModels: [WorkModel]) -> [PotentialTrack] {
        // Group lessons by subject and group (ignore empty groups)
        var groups: [String: [Lesson]] = [:] // Key: "subject|group"
        
        for lesson in lessons {
            let subject = lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            let group = lesson.group.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Ignore empty groups
            guard !group.isEmpty else { continue }
            guard !subject.isEmpty else { continue }
            
            let key = "\(subject)|\(group)"
            groups[key, default: []].append(lesson)
        }
        
        // Build lesson ID to group key mapping for efficient lookup
        var lessonIDToGroupKey: [UUID: String] = [:]
        for (key, groupLessons) in groups {
            for lesson in groupLessons {
                lessonIDToGroupKey[lesson.id] = key
            }
        }
        
        // Count history items (presentations and work models) for each group
        var historyCounts: [String: Int] = [:]
        
        for presentation in presentations {
            guard let lessonID = UUID(uuidString: presentation.lessonID),
                  let groupKey = lessonIDToGroupKey[lessonID] else { continue }
            historyCounts[groupKey, default: 0] += 1
        }
        
        for work in workModels {
            guard let lessonID = UUID(uuidString: work.lessonID),
                  let groupKey = lessonIDToGroupKey[lessonID] else { continue }
            historyCounts[groupKey, default: 0] += 1
        }
        
        // Filter out groups with zero history and map to PotentialTrack
        var tracks: [PotentialTrack] = []
        
        for (key, groupLessons) in groups {
            let historyCount = historyCounts[key] ?? 0
            
            // Filter out groups with zero history
            guard historyCount > 0 else { continue }
            
            // Parse subject and group from key
            let components = key.split(separator: "|", maxSplits: 1)
            guard components.count == 2 else { continue }
            let subject = String(components[0])
            let group = String(components[1])
            
            let track = PotentialTrack(
                id: key,
                subject: subject,
                group: group,
                lessonCount: groupLessons.count,
                historyCount: historyCount,
                isSelected: false
            )
            
            tracks.append(track)
        }
        
        // Sort by subject, then group
        tracks.sort { track1, track2 in
            if track1.subject != track2.subject {
                return track1.subject.localizedCaseInsensitiveCompare(track2.subject) == .orderedAscending
            }
            return track1.group.localizedCaseInsensitiveCompare(track2.group) == .orderedAscending
        }
        
        return tracks
    }
    
    private func selectAll() {
        for index in potentialTracks.indices {
            potentialTracks[index].isSelected = true
        }
    }
    
    private func deselectAll() {
        for index in potentialTracks.indices {
            potentialTracks[index].isSelected = false
        }
    }
    
    private func importSelectedTracks() {
        let selected = potentialTracks.filter { $0.isSelected }
        guard !selected.isEmpty else { return }
        
        isImporting = true
        importProgress = (0, selected.count, "")
        
        Task { @MainActor in
            do {
                // Fetch all required data on main actor
                let allLessons = try modelContext.fetch(FetchDescriptor<Lesson>())
                let allPresentations = try modelContext.fetch(FetchDescriptor<Presentation>())
                let allWorkModels = try modelContext.fetch(FetchDescriptor<WorkModel>())
                var existingEnrollments = try modelContext.fetch(FetchDescriptor<StudentTrackEnrollment>())
                
                // Process each selected track
                for (index, potentialTrack) in selected.enumerated() {
                    // Update progress
                    importProgress.current = index + 1
                    importProgress.currentTrack = "\(potentialTrack.subject) — \(potentialTrack.group)"
                    
                    // Process track and get any newly created enrollments
                    let newEnrollments = try processTrack(
                        potentialTrack: potentialTrack,
                        allLessons: allLessons,
                        allPresentations: allPresentations,
                        allWorkModels: allWorkModels,
                        existingEnrollments: existingEnrollments
                    )
                    
                    // Update existing enrollments list for next iteration
                    existingEnrollments.append(contentsOf: newEnrollments)
                }
                
                // Save context after all tracks are processed
                try modelContext.save()
                
                // Reset UI state
                isImporting = false
                importProgress = (0, 0, "")
                
                // Clear selection
                for index in potentialTracks.indices {
                    potentialTracks[index].isSelected = false
                }
                
                print("✅ Successfully imported \(selected.count) track(s)")
            } catch {
                print("❌ Error importing tracks: \(error)")
                isImporting = false
                importProgress = (0, 0, "")
            }
        }
    }
    
    @MainActor
    private func processTrack(
        potentialTrack: PotentialTrack,
        allLessons: [Lesson],
        allPresentations: [Presentation],
        allWorkModels: [WorkModel],
        existingEnrollments: [StudentTrackEnrollment]
    ) throws -> [StudentTrackEnrollment] {
        // 1. Find all lessons matching this subject and group
        let matchingLessons = allLessons.filter { lesson in
            let subject = lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            let group = lesson.group.trimmingCharacters(in: .whitespacesAndNewlines)
            return subject == potentialTrack.subject && group == potentialTrack.group
        }
        
        guard !matchingLessons.isEmpty else {
            print("⚠️ Warning: No lessons found for \(potentialTrack.subject) — \(potentialTrack.group)")
            return []
        }
        
        // 2. Create the Track
        let track = Track(
            title: "\(potentialTrack.subject) — \(potentialTrack.group)",
            createdAt: Date()
        )
        modelContext.insert(track)
        let trackIDString = track.id.uuidString
        
        // 3. Create TrackSteps (sorted by orderInGroup)
        let sortedLessons = matchingLessons.sorted { $0.orderInGroup < $1.orderInGroup }
        var steps: [TrackStep] = []
        
        for (index, lesson) in sortedLessons.enumerated() {
            let step = TrackStep(
                track: track,
                orderIndex: index,
                lessonTemplateID: lesson.id,
                createdAt: Date()
            )
            modelContext.insert(step)
            steps.append(step)
        }
        
        // Initialize track.steps relationship
        track.steps = steps
        
        // 4. Build set of lesson IDs for efficient lookup
        let lessonIDs = Set(matchingLessons.map { $0.id })
        
        // 5. Backfill history: Update Presentations
        var presentationDates: [Date] = []
        var studentIDsFromPresentations: Set<String> = []
        
        for presentation in allPresentations {
            guard let lessonID = UUID(uuidString: presentation.lessonID),
                  lessonIDs.contains(lessonID) else { continue }
            
            presentation.trackID = trackIDString
            
            // Collect date and student IDs
            presentationDates.append(presentation.presentedAt)
            studentIDsFromPresentations.formUnion(presentation.studentIDs)
        }
        
        // 6. Backfill history: Update WorkModels
        var workDates: [Date] = []
        var studentIDsFromWork: Set<String> = []
        
        for work in allWorkModels {
            guard let lessonID = UUID(uuidString: work.lessonID),
                  lessonIDs.contains(lessonID) else { continue }
            
            work.trackID = trackIDString
            
            // Collect date and student IDs
            let date = work.dueAt ?? work.createdAt
            workDates.append(date)
            if !work.studentID.isEmpty {
                studentIDsFromWork.insert(work.studentID)
            }
        }
        
        // 7. Auto-enroll students
        let allStudentIDs = studentIDsFromPresentations.union(studentIDsFromWork)
        let allDates = presentationDates + workDates
        let earliestDate = allDates.min()
        
        // Build set of existing enrollments for quick lookup
        let existingEnrollmentKeys = Set(existingEnrollments.map { "\($0.studentID)|\($0.trackID)" })
        
        var newEnrollments: [StudentTrackEnrollment] = []
        
        for studentID in allStudentIDs {
            let enrollmentKey = "\(studentID)|\(trackIDString)"
            
            // Check if enrollment already exists
            guard !existingEnrollmentKeys.contains(enrollmentKey) else { continue }
            
            let enrollment = StudentTrackEnrollment(
                studentID: studentID,
                trackID: trackIDString,
                startedAt: earliestDate,
                isActive: true
            )
            modelContext.insert(enrollment)
            newEnrollments.append(enrollment)
        }
        
        return newEnrollments
    }
}

// MARK: - PotentialTrack Model

struct PotentialTrack: Identifiable {
    let id: String
    let subject: String
    let group: String
    let lessonCount: Int
    let historyCount: Int
    var isSelected: Bool
}

// MARK: - TrackRow View

struct TrackRow: View {
    @Binding var track: PotentialTrack
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(track.subject) — \(track.group)")
                    .font(.headline)
                Text("\(track.lessonCount) lessons • \(track.historyCount) history items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $track.isSelected)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TrackPopulationView()
        .modelContainer(for: [
            Lesson.self,
            Presentation.self,
            WorkModel.self,
            Track.self,
            TrackStep.self,
            StudentTrackEnrollment.self
        ])
}
#endif
