import Foundation
import SwiftData

enum OrphanWorkLinkRepair {
    static func run(context: ModelContext) {
        do {
            let lessons = try context.fetch(FetchDescriptor<Lesson>())
            let lessonIDs = Set(lessons.map { $0.id })

            let contracts = try context.fetch(FetchDescriptor<WorkContract>())

            func resolves(_ lessonID: String) -> Bool {
                guard let u = UUID(uuidString: lessonID) else { return false }
                return lessonIDs.contains(u)
            }

            var fixed = 0
            var stillOrphan = 0
            var nonUUID = 0

            for c in contracts {
                if resolves(c.lessonID) { continue }
                if UUID(uuidString: c.lessonID) == nil { nonUUID += 1 }

                // Try Presentation bridge
                if let pidStr = c.presentationID,
                   let pid = UUID(uuidString: pidStr) {
                    var presDescriptor = FetchDescriptor<Presentation>(
                        predicate: #Predicate<Presentation> { $0.id == pid }
                    )
                    presDescriptor.fetchLimit = 1
                    if let pres = try? context.fetch(presDescriptor).first,
                       resolves(pres.lessonID) {
                        c.lessonID = pres.lessonID
                        fixed += 1
                        continue
                    }
                }

                // Try StudentLesson bridge
                if let sidStr = c.legacyStudentLessonID,
                   let sid = UUID(uuidString: sidStr) {
                    var slDescriptor = FetchDescriptor<StudentLesson>(
                        predicate: #Predicate<StudentLesson> { $0.id == sid }
                    )
                    slDescriptor.fetchLimit = 1
                    if let sl = try? context.fetch(slDescriptor).first,
                       let lesson = sl.lesson,
                       lessonIDs.contains(lesson.id) {
                        c.lessonID = lesson.id.uuidString
                        fixed += 1
                        continue
                    }
                }

                stillOrphan += 1
            }

            try context.save()
            print("ORPHAN REPAIR: fixed=\(fixed) stillOrphan=\(stillOrphan) nonUUIDLessonID=\(nonUUID)")
        } catch {
            print("ORPHAN REPAIR ERROR:", error)
        }
    }
}