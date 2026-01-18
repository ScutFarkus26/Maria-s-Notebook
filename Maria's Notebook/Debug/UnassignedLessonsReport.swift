#if DEBUG
import Foundation
import SwiftData

enum UnassignedLessonsReport {
    static func run(context: ModelContext) {
        do {
            let lessons = try context.fetch(FetchDescriptor<Lesson>())
            let unassigned = lessons.filter { $0.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            print("UNASSIGNED LESSONS: count=\(unassigned.count)")
            for l in unassigned.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
                print(" - \(l.name) [id=\(l.id)] group='\(l.group)' subheading='\(l.subheading)'")
            }
        } catch {
            print("UNASSIGNED LESSONS ERROR:", error)
        }
    }
}
#endif