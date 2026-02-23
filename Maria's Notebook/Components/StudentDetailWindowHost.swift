// StudentDetailWindowHost.swift
// Host view for displaying StudentDetailView in a separate macOS window.

import SwiftUI
import SwiftData

#if os(macOS)
struct StudentDetailWindowHost: View {
    let studentID: UUID
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let fetchDescriptor = FetchDescriptor<Student>(predicate: #Predicate { $0.id == studentID })
        if let student = modelContext.safeFetchFirst(fetchDescriptor) {
            StudentDetailView(student: student)
                .frame(minWidth: 500, minHeight: 400)
        } else {
            ContentUnavailableView("Student Not Found", systemImage: "person.slash")
                .frame(minWidth: 400, minHeight: 300)
        }
    }
}
#endif
