// StudentDetailWindowHost.swift
// Host view for displaying StudentDetailView in a separate macOS window.

import SwiftUI
import CoreData

#if os(macOS)
struct StudentDetailWindowHost: View {
    let studentID: UUID
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        if let student = viewContext.object(CDStudent.self, id: studentID) {
            StudentDetailView(student: student)
                .frame(minWidth: 500, minHeight: 400)
                .navigationTitle(student.fullName)
        } else {
            ContentUnavailableView("Student Not Found", systemImage: "person.slash")
                .frame(minWidth: 400, minHeight: 300)
        }
    }
}
#endif
