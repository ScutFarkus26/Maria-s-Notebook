// GreatLessonTagEditor.swift
// Sheet for tagging a lesson with its Great CDLesson connection.
// Simple picker with the 5 Great CDLesson options + "None".

import SwiftUI
import CoreData

struct GreatLessonTagEditor: View {
    @ObservedObject var lesson: CDLesson
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        NavigationStack {
            List {
                // None option
                Button {
                    lesson.greatLessonRaw = nil
                    viewContext.safeSave()
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

                // Great CDLesson options
                ForEach(GreatLesson.allCases) { gl in
                    Button {
                        lesson.greatLessonRaw = gl.rawValue
                        viewContext.safeSave()
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: gl.icon)
                                .font(.title3)
                                .foregroundStyle(gl.color)
                                .frame(width: 32, height: 32)
                                .background(
                                    gl.color.opacity(UIConstants.OpacityConstants.medium),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )

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
