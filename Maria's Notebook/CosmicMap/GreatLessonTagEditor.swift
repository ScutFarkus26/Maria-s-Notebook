// GreatLessonTagEditor.swift
// Sheet for tagging a lesson with its Great Lesson connection.
// Simple picker with the 5 Great Lesson options + "None".

import SwiftUI
import SwiftData

struct GreatLessonTagEditor: View {
    @Bindable var lesson: Lesson
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            List {
                // None option
                Button {
                    lesson.greatLessonRaw = nil
                    modelContext.safeSave()
                    dismiss()
                } label: {
                    HStack {
                        Label("None", systemImage: "minus.circle")
                            .foregroundStyle(.secondary)

                        Spacer()

                        if lesson.greatLessonRaw == nil {
                            Image(systemName: SFSymbol.Action.checkmarkCircleFill)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)

                // Great Lesson options
                ForEach(GreatLesson.allCases) { gl in
                    Button {
                        lesson.greatLessonRaw = gl.rawValue
                        modelContext.safeSave()
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: gl.icon)
                                .font(.title3)
                                .foregroundStyle(gl.color)
                                .frame(width: 32, height: 32)
                                .background(gl.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(gl.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)

                                Text(gl.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            if lesson.greatLessonRaw == gl.rawValue {
                                Image(systemName: SFSymbol.Action.checkmarkCircleFill)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Great Lesson")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        #endif
    }
}
