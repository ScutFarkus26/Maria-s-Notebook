import SwiftUI

struct MaintenanceSettingsView: View {
    @Binding var maintenanceAlert: (title: String, message: String)?
    let onMergeDuplicates: () -> Void
    let onPreviewDuplicates: () -> Void
    let onCleanupZeroStudentLessons: () -> Void

    var body: some View {
        SettingsGroup(title: "Maintenance", systemImage: "wrench.and.screwdriver") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        onMergeDuplicates()
                    } label: {
                        Label("Merge Duplicate Students", systemImage: "person.2.crop.square.stack")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        onPreviewDuplicates()
                    } label: {
                        Label("Preview Duplicates…", systemImage: "list.bullet.rectangle.portrait")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Text("Housekeeping tools to keep your data tidy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                Divider().padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        onCleanupZeroStudentLessons()
                    } label: {
                        Label("Remove Zero-Student Lessons", systemImage: "person.crop.circle.badge.xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Text("Deletes any Student Lesson records that have no students, and clears stale work links.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
