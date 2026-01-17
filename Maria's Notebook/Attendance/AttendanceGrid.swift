import SwiftUI
import SwiftData

struct AttendanceGrid: View {
    let students: [Student]
    let recordsByStudent: [String: AttendanceRecord]
    let onCycleStatus: (Student) -> Void
    let onUpdateNote: (Student, String?) -> Void
    let onUpdateAbsenceReason: (Student, AbsenceReason) -> Void
    
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 150, maximum: 280), spacing: 12)]
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(students, id: \.id) { student in
                    AttendanceCard(
                        student: student,
                        record: recordsByStudent[student.id.uuidString],
                        isEditing: true,
                        onTap: {
                            onCycleStatus(student)
                        },
                        onEditNote: { newNote in
                            onUpdateNote(student, newNote)
                        },
                        onSetAbsenceReason: { reason in
                            onUpdateAbsenceReason(student, reason)
                        }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
