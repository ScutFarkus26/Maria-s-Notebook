import SwiftUI
import SwiftData

struct WorksLogView: View {
    @Query(sort: [SortDescriptor(\WorkContract.createdAt, order: .reverse)])
    private var contracts: [WorkContract]
    
    @Query
    private var lessons: [Lesson]
    
    @Query
    private var students: [Student]
    
    private var lessonsById: [UUID: Lesson] {
        Dictionary(uniqueKeysWithValues: lessons.map { lesson in
            (lesson.id, lesson)
        })
    }
    
    private var studentsById: [UUID: Student] {
        Dictionary(uniqueKeysWithValues: students.map { student in
            (student.id, student)
        })
    }
    
    var body: some View {
        if contracts.isEmpty {
            Text("No recent work contracts")
                .foregroundColor(.secondary)
                .padding()
        } else {
            List(Array(contracts.prefix(50)), id: \.id) { contract in
                HStack {
                    VStack(alignment: .leading) {
                        Text(lessonName(for: contract))
                            .font(.headline)
                        Text(studentName(for: contract))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(String(describing: contract.status))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
        }
    }
    
    private func lessonName(for contract: WorkContract) -> String {
        if let lessonID = UUID(uuidString: contract.lessonID),
           let lesson = lessonsById[lessonID] {
            return lesson.name
        } else {
            return "Lesson"
        }
    }
    
    private func studentName(for contract: WorkContract) -> String {
        guard
            let studentID = UUID(uuidString: contract.studentID),
            let student = studentsById[studentID]
        else {
            return "Student"
        }
        return StudentFormatter.displayName(for: student)
    }
}

#Preview {
    WorksLogView()
        .modelContainer(try! ModelContainer(
            for: WorkContract.self, Lesson.self, Student.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ))
}
