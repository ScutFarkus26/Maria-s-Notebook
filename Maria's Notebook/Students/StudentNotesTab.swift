// StudentNotesTab.swift
// Notes tab content extracted from StudentDetailView

import SwiftUI
import SwiftData

struct StudentNotesTab: View {
    let student: Student
    
    // 1. Efficient Hybrid Fetch: Get notes for this student OR global notes
    @Query private var notes: [Note]
    @State private var showingSmartAssistant = false
    @State private var showingReportGenerator = false

    init(student: Student) {
        self.student = student
        let studentID = student.id
        
        let predicate = #Predicate<Note> { note in
            note.searchIndexStudentID == studentID || note.scopeIsAll == true
        }
        _notes = Query(filter: predicate, sort: \.updatedAt, order: .reverse)
    }

    var body: some View {
        StudentNotesTimelineView(student: student)
            .padding(.top, 16)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingReportGenerator = true
                    } label: {
                        Label("Generate Report", systemImage: "doc.text")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSmartAssistant = true
                    } label: {
                        Label("AI Assistant", systemImage: "sparkles")
                    }
                    .disabled(notes.isEmpty)
                }
            }
            .sheet(isPresented: $showingSmartAssistant) {
                AppleIntelligenceSheet(notes: notes)
                    #if os(iOS)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    #endif
            }
            .sheet(isPresented: $showingReportGenerator) {
                ReportGeneratorView(student: student)
            }
    }
}
