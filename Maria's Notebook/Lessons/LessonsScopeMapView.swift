// Maria's Notebook/Lessons/LessonsScopeMapView.swift
//
// Scope-and-sequence "Map" view: every group is one labeled row, every lesson
// is a small pill on that row, organized into a spine (Subject or Great Lesson).
// Tapping a thread row drills into LessonsScopeThreadFocusView.

import SwiftUI
import CoreData

struct LessonsScopeMapView: View {
    let lessons: [CDLesson]
    /// Optional subject filter (nil = show all subjects).
    /// Ignored when `spine == .greatLesson` — the Great Lesson spine is intentionally cross-subject.
    let selectedSubject: String?
    @Binding var spine: MapSpine
    let onSelectThread: (ThreadKey) -> Void

    private let helper = LessonsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                spinePicker

                ForEach(sections) { section in
                    sectionView(section)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func sectionView(_ section: MapSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let icon = section.icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(section.title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.8)
            }
            .foregroundStyle(section.color)
            .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(section.rows) { row in
                    ThreadRow(
                        threadKey: row.key,
                        lessons: row.lessons,
                        color: AppColors.color(forSubject: row.key.subject),
                        onTap: { onSelectThread(row.key) }
                    )
                }
            }
        }
    }

    private var spinePicker: some View {
        HStack(spacing: 8) {
            Text("Spine")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            Picker("Spine", selection: $spine) {
                ForEach(MapSpine.allCases) { option in
                    Label(option.rawValue, systemImage: option.icon).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)

            Spacer()
        }
        .padding(.bottom, 4)
    }

    // MARK: - Sections

    private var sections: [MapSection] {
        switch spine {
        case .subject:
            return subjectSections()
        case .greatLesson:
            return greatLessonSections()
        }
    }

    private func subjectSections() -> [MapSection] {
        let subjects: [String]
        if let selectedSubject, !selectedSubject.trimmed().isEmpty {
            subjects = [selectedSubject]
        } else {
            subjects = helper.subjects(from: lessons)
        }

        return subjects.compactMap { subject -> MapSection? in
            let rows = threadRowsForSubject(subject, lessons: lessonsInSubject(subject))
            guard !rows.isEmpty else { return nil }
            return MapSection(
                id: "subject:\(subject)",
                title: subject,
                color: AppColors.color(forSubject: subject),
                icon: nil,
                rows: rows
            )
        }
    }

    private func greatLessonSections() -> [MapSection] {
        // Spine ignores subject filter — Great Lesson is intentionally cross-subject.
        var unassigned: [CDLesson] = []
        var byGreatLesson: [GreatLesson: [CDLesson]] = [:]

        for lesson in lessons {
            let resolved = GreatLesson.resolve(for: lesson)
            if let primary = resolved.first {
                byGreatLesson[primary, default: []].append(lesson)
            } else {
                unassigned.append(lesson)
            }
        }

        var result: [MapSection] = []
        for greatLesson in GreatLesson.allCases {
            guard let bucket = byGreatLesson[greatLesson], !bucket.isEmpty else { continue }
            let rows = threadRowsAcrossSubjects(lessons: bucket)
            guard !rows.isEmpty else { continue }
            result.append(MapSection(
                id: "greatLesson:\(greatLesson.rawValue)",
                title: greatLesson.shortName,
                color: greatLesson.color,
                icon: greatLesson.icon,
                rows: rows
            ))
        }

        if !unassigned.isEmpty {
            let rows = threadRowsAcrossSubjects(lessons: unassigned)
            if !rows.isEmpty {
                result.append(MapSection(
                    id: "greatLesson:unassigned",
                    title: "Unassigned",
                    color: .secondary,
                    icon: "questionmark.circle",
                    rows: rows
                ))
            }
        }

        return result
    }

    // MARK: - Thread row builders

    private func lessonsInSubject(_ subject: String) -> [CDLesson] {
        let key = subject.trimmed().lowercased()
        return lessons.filter { $0.subject.trimmed().lowercased() == key }
    }

    /// Thread rows for a single subject — order respects FilterOrderStore via `helper.groups`.
    private func threadRowsForSubject(_ subject: String, lessons subjectLessons: [CDLesson]) -> [ThreadRowData] {
        let groups = helper.groups(for: subject, lessons: lessons)
        var rows: [ThreadRowData] = []

        for group in groups {
            let groupKey = group.trimmed().lowercased()
            let inGroup = subjectLessons
                .filter { $0.group.trimmed().lowercased() == groupKey }
                .sorted(by: ThreadRowData.lessonSortOrder)
            if !inGroup.isEmpty {
                rows.append(ThreadRowData(
                    key: ThreadKey(subject: subject, group: group),
                    lessons: inGroup
                ))
            }
        }

        let ungrouped = subjectLessons
            .filter { $0.group.trimmed().isEmpty }
            .sorted(by: ThreadRowData.lessonSortOrder)
        if !ungrouped.isEmpty {
            rows.append(ThreadRowData(
                key: ThreadKey(subject: subject, group: ""),
                lessons: ungrouped
            ))
        }

        return rows
    }

    /// Thread rows aggregated from a heterogeneous lesson set. Used by Great Lesson spine
    /// where one section spans multiple subjects. Subjects are interleaved alphabetically
    /// within the section so threads stay grouped by their parent subject.
    private func threadRowsAcrossSubjects(lessons bucket: [CDLesson]) -> [ThreadRowData] {
        let bySubject = Dictionary(grouping: bucket) { $0.subject.trimmed() }
        let orderedSubjects = bySubject.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        var rows: [ThreadRowData] = []
        for subject in orderedSubjects {
            guard !subject.isEmpty, let subjectLessons = bySubject[subject] else { continue }
            rows.append(contentsOf: threadRowsForSubject(subject, lessons: subjectLessons))
        }

        // Lessons with no subject — extremely unusual, but render as a final unassigned thread.
        if let subjectless = bySubject[""], !subjectless.isEmpty {
            let sorted = subjectless.sorted(by: ThreadRowData.lessonSortOrder)
            rows.append(ThreadRowData(
                key: ThreadKey(subject: "", group: ""),
                lessons: sorted
            ))
        }
        return rows
    }
}

// MARK: - Section model

struct MapSection: Identifiable {
    let id: String
    let title: String
    let color: Color
    let icon: String?
    let rows: [ThreadRowData]
}

struct ThreadRowData: Identifiable {
    let key: ThreadKey
    let lessons: [CDLesson]

    var id: String { key.id }

    static func lessonSortOrder(_ lhs: CDLesson, _ rhs: CDLesson) -> Bool {
        if lhs.orderInGroup != rhs.orderInGroup {
            return lhs.orderInGroup < rhs.orderInGroup
        }
        let nameCompare = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameCompare != .orderedSame {
            return nameCompare == .orderedAscending
        }
        return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
    }
}
