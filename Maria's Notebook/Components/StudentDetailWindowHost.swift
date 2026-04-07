// StudentDetailWindowHost.swift
// Host view for displaying StudentDetailView in a separate macOS window.

import SwiftUI
import CoreData

#if os(macOS)
struct StudentDetailWindowHost: View {
    let studentID: UUID
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        let fetchDescriptor = { let r = CDStudent.fetchRequest() as! NSFetchRequest<CDStudent>; r.predicate = NSPredicate(format: "id == %@", studentID as CVarArg); return r }()
        if let student = viewContext.safeFetchFirst(fetchDescriptor) {
            StudentDetailView(student: student)
                .frame(minWidth: 500, minHeight: 400)
        } else {
            ContentUnavailableView("Student Not Found", systemImage: "person.slash")
                .frame(minWidth: 400, minHeight: 300)
        }
    }
}
#endif
