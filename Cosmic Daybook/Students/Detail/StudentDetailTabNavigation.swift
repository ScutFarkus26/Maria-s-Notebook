// StudentDetailTabNavigation.swift
// Tab navigation component extracted from StudentDetailView

import SwiftUI
import CoreData

/// The durable, plain-language structure of a student's record. The earlier
/// eight-tab implementation exposed the application's storage features instead
/// of the guide's work: observe, understand learning, and meet with a child.
enum StudentWorkspaceSection: String, CaseIterable, Identifiable {
    case overview
    case observe
    case learning
    case meetings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .observe: "Observe"
        case .learning: "Learning"
        case .meetings: "Meetings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "person.crop.circle"
        case .observe: "note.text"
        case .learning: "book.closed"
        case .meetings: "person.2"
        }
    }

    /// Read the old persisted tab value without stranding a guide in an empty
    /// section after the redesign ships.
    static func migrating(storedValue: String) -> StudentWorkspaceSection {
        if let section = StudentWorkspaceSection(rawValue: storedValue) {
            return section
        }
        switch storedValue {
        case "notes", "developmentalTraits": return .observe
        case "progress", "history", "yearPlan": return .learning
        case "meetings": return .meetings
        case "files": return .overview
        default: return .overview
        }
    }
}

struct StudentWorkspaceSectionPicker: View {
    @Binding var selectedSection: StudentWorkspaceSection

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @ViewBuilder
    var body: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            sectionPicker
                .pickerStyle(.menu)
        } else {
            sectionPicker
                .pickerStyle(.segmented)
        }
        #else
        sectionPicker
            .pickerStyle(.segmented)
        #endif
    }

    private var sectionPicker: some View {
        Picker("Student section", selection: $selectedSection) {
            ForEach(StudentWorkspaceSection.allCases) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
        }
        .labelsHidden()
        .accessibilityLabel("Student section")
    }
}
