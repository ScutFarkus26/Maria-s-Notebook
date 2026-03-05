import SwiftUI
import SwiftData

extension LessonDetailCard {
    var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let url = resolvedPagesURL {
                HStack { Spacer() }
                OpenInPagesButton(title: "Open in Pages") { openInPages(url) }
                    .padding(.vertical, 8)
                HStack { Spacer() }
            }

            // Purpose
            if !lesson.purpose.trimmed().isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: "target")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Purpose")
                            .font(AppTheme.ScaledFont.calloutSemibold)
                            .foregroundStyle(.secondary)
                    }
                    Text(lesson.purpose)
                        .font(AppTheme.ScaledFont.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 6)
            }

            // Materials
            if !lesson.materialsItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: "tray.full")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Materials")
                            .font(AppTheme.ScaledFont.calloutSemibold)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(lesson.materialsItems, id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\u{2022}").font(AppTheme.ScaledFont.body)
                                Text(item)
                                    .font(AppTheme.ScaledFont.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }

            // Presentation Notes (writeUp)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.plaintext")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text("Presentation Notes")
                        .font(AppTheme.ScaledFont.calloutSemibold)
                        .foregroundStyle(.secondary)
                }
                if lesson.writeUp.trimmed().isEmpty {
                    Text("No notes yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        Text(lesson.writeUp)
                            .font(AppTheme.ScaledFont.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 180, maxHeight: 360)
                }
            }
            .padding(.top, 6)

            // Teacher Notes
            if !lesson.teacherNotes.trimmed().isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: "note.text")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Teacher Notes")
                            .font(AppTheme.ScaledFont.calloutSemibold)
                            .foregroundStyle(.secondary)
                    }
                    Text(lesson.teacherNotes)
                        .font(AppTheme.ScaledFont.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 6)
            }

            // Exercises
            if !lesson.sortedExercises.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(lesson.sortedExercises) { exercise in
                            LessonExerciseRow(exercise: exercise)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "list.number")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Exercises (\(lesson.sortedExercises.count))")
                            .font(AppTheme.ScaledFont.calloutSemibold)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
            }

            // Prerequisites
            if !lesson.prerequisiteLessonUUIDs.isEmpty {
                LessonRelationshipsSection(
                    title: "Prerequisites",
                    icon: "arrow.backward.circle",
                    lessonIDs: lesson.prerequisiteLessonUUIDs,
                    modelContext: modelContext
                )
            }

            // Related Lessons
            if !lesson.relatedLessonUUIDs.isEmpty {
                LessonRelationshipsSection(
                    title: "Related Lessons",
                    icon: "link",
                    lessonIDs: lesson.relatedLessonUUIDs,
                    modelContext: modelContext
                )
            }
        }
    }
}
