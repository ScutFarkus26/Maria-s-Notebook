// StudentNotesTab.swift
// Notes tab content extracted from StudentDetailView

import SwiftUI
import CoreData

struct StudentNotesTab: View {
    let student: CDStudent
    
    // 1. Efficient Hybrid Fetch: Get notes for this student OR global notes
    @FetchRequest(sortDescriptors: []) private var notes: FetchedResults<CDNote>
    @State private var showingSmartAssistant = false
    @State private var showingReportGenerator = false

    init(student: CDStudent) {
        self.student = student

        let predicate: NSPredicate
        if let studentID = student.id {
            predicate = NSPredicate(format: "searchIndexStudentID == %@ OR scopeIsAll == YES", studentID as CVarArg)
        } else {
            predicate = NSPredicate(format: "scopeIsAll == YES")
        }
        _notes = FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDNote.updatedAt, ascending: false)], predicate: predicate)
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
                AppleIntelligenceSheet(notes: Array(notes))
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
