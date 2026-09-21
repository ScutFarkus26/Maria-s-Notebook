import SwiftUI
import CoreData

struct StudentPillsSection: View {
    let students: [CDStudent]
    /// The lesson this group is for, when there is one. Given it, a chip for a
    /// child who already has the lesson on record carries the same caption the
    /// picker shows, so the warning survives the picker being dismissed.
    var lessonOnRecord: CDLesson?
    let areaColor: Color
    var onRemove: (UUID) -> Void
    var onOpenPicker: () -> Void
    var onOpenMove: () -> Void
    let canMoveStudents: Bool
    var onOpenFindStudents: () -> Void
    var onOpenMoveAbsent: () -> Void
    let canMoveAbsentStudents: Bool

    @Environment(\.managedObjectContext) private var viewContext

    /// What the record holds for `lessonOnRecord`, read once when there is one.
    @State private var records: [UUID: PresentationRecordIndex.Given] = [:]

    var body: some View {
        VStack(spacing: 12) {
            FlowLayout(spacing: 8) {
                ForEach(students, id: \.id) { student in
                    studentChip(for: student)
                }
            }

            HStack(spacing: 12) {
                Button(action: onOpenPicker) {
                    Label("Add/Remove Students", systemImage: "person.2.badge.gearshape")
                        .font(AppTheme.ScaledFont.callout)
                }
                .buttonStyle(.bordered)

                Button(action: onOpenFindStudents) {
                    Label("Find Students", systemImage: "person.badge.plus")
                        .font(AppTheme.ScaledFont.callout)
                }
                .buttonStyle(.bordered)

                if canMoveStudents {
                    Button(action: onOpenMove) {
                        Label("Move Students", systemImage: "arrow.right.square")
                            .font(AppTheme.ScaledFont.callout)
                    }
                    .buttonStyle(.bordered)
                }

                if canMoveAbsentStudents {
                    Button(action: onOpenMoveAbsent) {
                        Label("Move Absent Students", systemImage: "person.fill.xmark")
                            .font(AppTheme.ScaledFont.callout)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: lessonOnRecord?.id) { loadRecord() }
    }

    private func loadRecord() {
        guard let lessonID = lessonOnRecord?.id else {
            records = [:]
            return
        }
        let index = PresentationRecordIndex(lessonIDs: [lessonID.uuidString], in: viewContext)
        records = StudentPickerModel.records(from: index, lesson: lessonID)
    }

    private func studentChip(for student: CDStudent) -> some View {
        HStack(spacing: 6) {
            Text(student.shortName)
                .font(AppTheme.ScaledFont.captionSemibold)
            if let given = student.id.flatMap({ records[$0] }) {
                StudentRecordCaption(given: given, compact: true)
            }
            Button { if let id = student.id { onRemove(id) } } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(areaColor)
            .accessibilityLabel("Remove \(student.shortName)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(areaColor)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(areaColor.opacity(UIConstants.OpacityConstants.accent))
        )
    }
}
