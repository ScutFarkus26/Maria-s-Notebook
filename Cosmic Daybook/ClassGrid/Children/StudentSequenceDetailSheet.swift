// StudentSequenceDetailSheet.swift
// Modal opened when the user taps a student's sequence row in the Progress dashboard.
// Three tabs: Work, Presentations, and Notes — all scoped to this student in this
// (subject, area) sequence. Data loading lives in StudentSequenceDetailLoader; row
// views live in StudentSequenceDetailRows.

import SwiftUI
import CoreData

/// Routing payload — Identifiable so .sheet(item:) drives presentation.
struct StudentSequenceDetailTarget: Identifiable {
    let id: String  // "\(studentID)|\(area)|\(sequence)"
    let studentID: UUID
    let studentName: String
    let area: String
    let sequence: String
    let lessonIDs: [UUID]

    init(studentID: UUID, studentName: String, area: String, sequence: String, lessonIDs: [UUID]) {
        self.id = "\(studentID)|\(area)|\(sequence)"
        self.studentID = studentID
        self.studentName = studentName
        self.area = area
        self.sequence = sequence
        self.lessonIDs = lessonIDs
    }
}

enum StudentSequenceDetailTab: String, CaseIterable, Identifiable {
    case work = "Work"
    case presentations = "Presentations"
    case notes = "Notes"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .work:          return "tray.full"
        case .presentations: return "calendar"
        case .notes:         return "note.text"
        }
    }
}

struct StudentSequenceDetailSheet: View {
    let target: StudentSequenceDetailTarget
    let onClose: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedTab: StudentSequenceDetailTab = .presentations
    @State private var detail: StudentSequenceDetail?

    private var areaColor: Color { AppColors.color(forArea: target.area) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerSection
                tabPicker
                Divider()
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(target.studentName)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onClose() }
                }
            }
            .task {
                detail = StudentSequenceDetailLoader.load(target: target, context: viewContext)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(areaColor)
                .frame(width: 10, height: 10)
            Text(target.area.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(areaColor)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(target.sequence)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(StudentSequenceDetailTab.allCases) { tab in
                Label(tabTitle(tab), systemImage: tab.icon).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private func tabTitle(_ tab: StudentSequenceDetailTab) -> String {
        switch tab {
        case .work:          return "Work (\(detail?.work.count ?? 0))"
        case .presentations: return "Presented (\(detail?.presentations.count ?? 0))"
        case .notes:         return "Notes (\(detail?.notes.count ?? 0))"
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        if let detail {
            ScrollView {
                Group {
                    switch selectedTab {
                    case .work:          workList(detail.work)
                    case .presentations: presentationsList(detail.presentations)
                    case .notes:         notesList(detail.notes)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func workList(_ items: [WorkDetailItem]) -> some View {
        if items.isEmpty {
            SequenceDetailEmptyMessage(icon: "tray", text: "No work items in this area yet.")
        } else {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    SequenceDetailWorkRow(item: item)
                }
            }
        }
    }

    @ViewBuilder
    private func presentationsList(_ items: [PresentationDetailItem]) -> some View {
        if items.isEmpty {
            SequenceDetailEmptyMessage(
                icon: "calendar.badge.exclamationmark",
                text: "No presentations given in this area yet."
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    SequenceDetailPresentationRow(item: item, areaColor: areaColor)
                }
            }
        }
    }

    @ViewBuilder
    private func notesList(_ items: [NoteDetailItem]) -> some View {
        if items.isEmpty {
            SequenceDetailEmptyMessage(icon: "note", text: "No notes tagged to lessons in this area yet.")
        } else {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    SequenceDetailNoteRow(item: item)
                }
            }
        }
    }
}
