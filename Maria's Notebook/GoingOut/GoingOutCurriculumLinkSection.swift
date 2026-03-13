// GoingOutCurriculumLinkSection.swift
// Shows linked curriculum lessons with subject colors.

import SwiftUI
import SwiftData

struct GoingOutCurriculumLinkSection: View {
    @Bindable var goingOut: GoingOut
    @Environment(\.modelContext) private var modelContext
    @State private var showingLessonPicker = false

    private var linkedLessons: [Lesson] {
        let uuids = goingOut.curriculumLinkUUIDs
        guard !uuids.isEmpty else { return [] }

        let descriptor = FetchDescriptor<Lesson>()
        let allLessons = modelContext.safeFetch(descriptor)
        return allLessons.filter { uuids.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Curriculum Links")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    showingLessonPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption2)
                        Text("Link")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            if linkedLessons.isEmpty {
                Text("No curriculum links yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(linkedLessons) { lesson in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(AppColors.color(forSubject: lesson.subject))
                                .frame(width: 6, height: 6)
                            Text(lesson.name)
                                .font(.caption2)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Button {
                                removeLink(lesson)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppColors.color(forSubject: lesson.subject).opacity(0.1))
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showingLessonPicker) {
            lessonPickerSheet
        }
    }

    // MARK: - Lesson Picker

    private var lessonPickerSheet: some View {
        NavigationStack {
            LessonPickerList(
                selectedIDs: Set(goingOut.curriculumLinkUUIDs),
                onToggle: { lessonID in
                    var current = goingOut.curriculumLinkUUIDs
                    if current.contains(lessonID) {
                        current.removeAll { $0 == lessonID }
                    } else {
                        current.append(lessonID)
                    }
                    goingOut.curriculumLinkUUIDs = current
                    goingOut.modifiedAt = Date()
                    modelContext.safeSave()
                }
            )
            .navigationTitle("Link Lessons")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingLessonPicker = false }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func removeLink(_ lesson: Lesson) {
        var current = goingOut.curriculumLinkUUIDs
        current.removeAll { $0 == lesson.id }
        goingOut.curriculumLinkUUIDs = current
        goingOut.modifiedAt = Date()
        modelContext.safeSave()
    }
}

// MARK: - Lesson Picker List

private struct LessonPickerList: View {
    let selectedIDs: Set<UUID>
    let onToggle: (UUID) -> Void

    @Query(sort: [SortDescriptor(\Lesson.subject), SortDescriptor(\Lesson.sortIndex)])
    private var lessons: [Lesson]

    @State private var searchText = ""

    private var filteredLessons: [Lesson] {
        guard !searchText.isEmpty else { return lessons }
        let query = searchText.lowercased()
        return lessons.filter {
            $0.name.lowercased().contains(query) ||
            $0.subject.lowercased().contains(query)
        }
    }

    var body: some View {
        List {
            ForEach(filteredLessons) { lesson in
                Button {
                    onToggle(lesson.id)
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(AppColors.color(forSubject: lesson.subject))
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(lesson.name)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(lesson.subject)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if selectedIDs.contains(lesson.id) {
                            Image(systemName: SFSymbol.Action.checkmarkCircleFill)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search lessons")
    }
}
