// StudentNotesTab.swift
// Notes tab content extracted from StudentDetailView

import SwiftUI
import CoreData

struct StudentNotesTab: View {
    let student: CDStudent

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @State private var showingSmartAssistant = false
    @State private var showingReportGenerator = false
    /// The notes Writing Help drafts from, gathered when it opens.
    @State private var writingHelpNotes: [CDNote] = []
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    init(student: CDStudent) {
        self.student = student
    }

    var body: some View {
        StudentNotesTimelineView(student: student)
            .padding(.top, 16)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        #if os(macOS)
                        if let studentID = student.id {
                            openWindow(id: "StudentReportWindow", value: studentID)
                        }
                        #else
                        showingReportGenerator = true
                        #endif
                    } label: {
                        Label("Generate Report", systemImage: "doc.text")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openWritingHelp()
                    } label: {
                        Label("AI Assistant", systemImage: "sparkles")
                    }
                }
            }
            .sheet(isPresented: $showingSmartAssistant) {
                AppleIntelligenceSheet(notes: writingHelpNotes)
                    #if os(iOS)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    #endif
            }
            .sheet(isPresented: $showingReportGenerator) {
                ReportGeneratorView(student: student)
            }
    }

    /// Writing Help drafts from the notes this tab shows — group notes
    /// included — from this school year. It used to read only her own notes
    /// and every year's whole-class notes.
    private func openWritingHelp() {
        let notesTab = StudentNotesViewModel(
            student: student, viewContext: viewContext, saveCoordinator: dependencies.saveCoordinator
        )
        writingHelpNotes = notesTab.writingHelpNotes(in: dependencies.schoolYearStore.current.range)
        showingSmartAssistant = true
    }
}
