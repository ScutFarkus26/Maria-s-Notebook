// StudentNotesTab.swift
// Notes tab content extracted from StudentDetailView

import SwiftUI
import SwiftData

struct StudentNotesTab: View {
    let student: Student

    var body: some View {
        StudentNotesTimelineView(student: student)
            .padding(.top, 16)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
    }
}

