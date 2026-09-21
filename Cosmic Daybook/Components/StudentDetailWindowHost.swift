// StudentDetailWindowHost.swift
// Host view for displaying StudentDetailView in a separate macOS window.

import CoreData
import SwiftUI

#if os(macOS)
struct StudentDetailWindowHost: View {
    let studentID: UUID

    var body: some View {
        EntityWindowHost(
            id: studentID,
            minSize: CGSize(width: 500, height: 400),
            notFound: WindowHostNotFound(
                "Student Not Found",
                systemImage: "person.slash",
                minSize: CGSize(width: 400, height: 300)
            )
        ) { (student: CDStudent) in
            StudentDetailView(student: student)
                .navigationTitle(student.fullName)
        }
    }
}
#endif
