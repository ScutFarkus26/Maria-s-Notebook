import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

/// View that displays CloudKit sync status and record counts
struct CloudKitStatusView: View {
    @Environment(\.modelContext) private var modelContext
    
    // Queries for all entity types to count records
    @Query private var students: [Student]
    @Query private var lessons: [Lesson]
    @Query private var studentLessons: [StudentLesson]
    @Query private var workModels: [WorkModel]
    @Query private var workPlanItems: [WorkPlanItem]
    @Query private var workCompletionRecords: [WorkCompletionRecord]
    @Query private var attendanceRecords: [AttendanceRecord]
    @Query private var notes: [Note]
    @Query private var projects: [Project]
    @Query private var projectSessions: [ProjectSession]
    @Query private var presentations: [Presentation]
    @Query private var studentMeetings: [StudentMeeting]
    @Query private var communityTopics: [CommunityTopic]
    
    private var isCloudKitEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.enableCloudKitSync)
    }
    
    private var isCloudKitActive: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.cloudKitActive)
    }
    
    private var containerID: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "Unknown"
        return "iCloud.\(bundleID)"
    }
    
    private var totalRecordCount: Int {
        students.count +
        lessons.count +
        studentLessons.count +
        workModels.count +
        workPlanItems.count +
        workCompletionRecords.count +
        attendanceRecords.count +
        notes.count +
        projects.count +
        projectSessions.count +
        presentations.count +
        studentMeetings.count +
        communityTopics.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status Header
            HStack {
                Circle()
                    .fill(isCloudKitActive ? Color.green : (isCloudKitEnabled ? Color.orange : Color.gray))
                    .frame(width: 12, height: 12)
                Text(isCloudKitActive ? "CloudKit Active" : (isCloudKitEnabled ? "CloudKit Enabled (Restart Required)" : "CloudKit Disabled"))
                    .font(.headline)
            }
            
            if isCloudKitEnabled || isCloudKitActive {
                Divider()
                
                // Container Info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Container ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(containerID)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                
                Divider()
                
                // Record Counts
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Total Records")
                            .font(.headline)
                        Spacer()
                        Text("\(totalRecordCount)")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            RecordCountRow(name: "Students", count: students.count)
                            RecordCountRow(name: "Lessons", count: lessons.count)
                            RecordCountRow(name: "Student Lessons", count: studentLessons.count)
                            RecordCountRow(name: "Work Models", count: workModels.count)
                            RecordCountRow(name: "Work Plan Items", count: workPlanItems.count)
                            RecordCountRow(name: "Work Completions", count: workCompletionRecords.count)
                            RecordCountRow(name: "Attendance Records", count: attendanceRecords.count)
                            RecordCountRow(name: "Notes", count: notes.count)
                            RecordCountRow(name: "Projects", count: projects.count)
                            RecordCountRow(name: "Project Sessions", count: projectSessions.count)
                            RecordCountRow(name: "Presentations", count: presentations.count)
                            RecordCountRow(name: "Student Meetings", count: studentMeetings.count)
                            RecordCountRow(name: "Community Topics", count: communityTopics.count)
                        }
                    }
                    .frame(maxHeight: 200)
                }
                
                Divider()
                
                // Info Text
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync Status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isCloudKitActive {
                        Text("CloudKit is active and syncing. Data should appear in CloudKit Console and on other devices.")
                            .font(.caption)
                    } else if isCloudKitEnabled {
                        Text("CloudKit is enabled but not yet active. Restart the app to activate CloudKit sync.")
                            .font(.caption)
                    } else {
                        Text("CloudKit is disabled. Enable it above to sync data across devices.")
                            .font(.caption)
                    }
                }
            } else {
                Text("Enable CloudKit above to start syncing data to iCloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #else
        .background(Color(.systemGray6))
        #endif
        .cornerRadius(8)
    }
}

private struct RecordCountRow: View {
    let name: String
    let count: Int
    
    var body: some View {
        HStack {
            Text(name)
                .font(.caption)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

