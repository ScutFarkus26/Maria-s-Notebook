import Foundation
import SwiftUI

@Observable
final class WorkFilters {
    var searchText: String = ""
    var selectedSubject: String?
    var selectedStudentIDs: Set<UUID> = []
    var selectedWorkType: WorkModel.WorkType?
    var grouping: Grouping = .none
    
    enum Grouping: String, CaseIterable {
        case none, type, date, checkIns
        
        var displayName: String {
            switch self {
            case .none: return "None"
            case .type: return "Type"
            case .date: return "Date"
            case .checkIns: return "Check Ins"
            }
        }
        
        var icon: String {
            switch self {
            case .none: return "rectangle.3.group"
            case .type: return "square.grid.2x2"
            case .date: return "calendar"
            case .checkIns: return "checklist"
            }
        }
    }
    
    func filterWorks(
        _ works: [WorkModel],
        studentLessonsByID: [UUID: StudentLesson],
        lessonsByID: [UUID: Lesson]
    ) -> [WorkModel] {
        var base = works
        
        // Subject filter (via linked StudentLesson -> Lesson.subject)
        if let subject = selectedSubject {
            base = base.filter { work in
                guard let slID = work.studentLessonID,
                      let sl = studentLessonsByID[slID],
                      let lesson = lessonsByID[sl.lessonID] else { return false }
                return lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(subject) == .orderedSame
            }
        }
        
        // Student filter (works that include ANY of the selected students)
        if !selectedStudentIDs.isEmpty {
            base = base.filter { !Set($0.studentIDs).isDisjoint(with: selectedStudentIDs) }
        }
        
        // Text search on notes, title and linked lesson name
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            base = base.filter { work in
                let notesMatch = work.notes.lowercased().contains(query)
                let titleMatch = work.title.lowercased().contains(query)
                var lessonMatch = false
                if let slID = work.studentLessonID,
                   let sl = studentLessonsByID[slID],
                   let lesson = lessonsByID[sl.lessonID] {
                    lessonMatch = lesson.name.lowercased().contains(query)
                }
                return titleMatch || notesMatch || lessonMatch
            }
        }
        
        return base
    }
    
    func clear() {
        searchText = ""
        selectedSubject = nil
        selectedStudentIDs = []
        selectedWorkType = nil
        grouping = .none
    }
}
