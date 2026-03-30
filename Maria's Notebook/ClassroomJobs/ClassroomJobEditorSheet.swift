// ClassroomJobEditorSheet.swift
// Create/edit form for classroom jobs.

import SwiftUI
import SwiftData

struct ClassroomJobEditorSheet: View {
    let existingJob: ClassroomJob?
    let viewModel: ClassroomJobsViewModel
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var jobDescription = ""
    @State private var selectedIcon = "star"
    @State private var selectedColor = "blue"
    @State private var maxStudents = 1

    private let iconOptions = [
        "star", "leaf", "drop", "trash", "book",
        "pencil", "scissors", "paintbrush", "music.note", "bell",
        "flag", "heart", "lightbulb", "hand.raised", "figure.walk",
        "cup.and.saucer", "fork.knife", "tray", "archivebox", "key"
    ]

    private let colorOptions = ["red", "orange", "yellow", "green", "blue", "purple", "pink", "gray"]

    private var isEditing: Bool { existingJob != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Job Details") {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $jobDescription)
                    Stepper("Max Students: \(maxStudents)", value: $maxStudents, in: 1...10)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title3)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(selectedIcon == icon
                                                  ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent)
                                                  : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(selectedIcon == icon
                                                    ? Color.accentColor
                                                    : Color.clear, lineWidth: 1.5)
                                    )
                                    .foregroundStyle(selectedIcon == icon ? Color.accentColor : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Color") {
                    HStack(spacing: 8) {
                        ForEach(colorOptions, id: \.self) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(colorForRaw(color))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: selectedColor == color ? 2 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Job" : "New Job")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        save()
                        dismiss()
                    }
                    .disabled(name.trimmed().isEmpty)
                }
            }
            .onAppear { seedFromExisting() }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func seedFromExisting() {
        guard let job = existingJob else { return }
        name = job.name
        jobDescription = job.jobDescription
        selectedIcon = job.icon
        selectedColor = job.colorRaw
        maxStudents = job.maxStudents
    }

    private func save() {
        let fields = ClassroomJobFields(
            name: name.trimmed(),
            description: jobDescription.trimmed(),
            icon: selectedIcon,
            colorRaw: selectedColor,
            maxStudents: maxStudents
        )
        if let job = existingJob {
            viewModel.updateJob(job, with: fields, context: modelContext)
        } else {
            viewModel.createJob(fields, context: modelContext)
        }
    }

    private func colorForRaw(_ raw: String) -> Color {
        switch raw {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        default: return .gray
        }
    }
}
