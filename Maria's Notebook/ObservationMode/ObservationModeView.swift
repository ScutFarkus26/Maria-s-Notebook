// ObservationModeView.swift
// Dedicated observation recording interface with Montessori-specific prompts,
// quick-tag buttons, timer, and student selection.
// Creates standard Notes via the existing Note system.

import SwiftUI
import SwiftData

struct ObservationModeView: View {
    @Environment(\.modelContext) private var modelContext
    @State var viewModel = ObservationModeViewModel()
    @State private var showingPatterns = false
    @State private var selectedTab: ObserveTab = .record

    private enum ObserveTab: String, CaseIterable {
        case record = "Record"
        case heatmap = "Heatmap"
    }

    // Change detection
    @Query(sort: [SortDescriptor(\Note.createdAt, order: .reverse)])
    private var notesForChange: [Note]
    private var noteChangeToken: Int { notesForChange.count }

    var body: some View {
        Group {
            switch selectedTab {
            case .record:
                content
            case .heatmap:
                ObservationHeatmapView()
            }
        }
        .navigationTitle("Observe")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Tab", selection: $selectedTab) {
                    ForEach(ObserveTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingPatterns = true
                } label: {
                    Label("Patterns", systemImage: SFSymbol.Chart.chartBar)
                }
            }
        }
        .onAppear { viewModel.loadData(context: modelContext) }
        .sheet(isPresented: $showingPatterns) {
            NavigationStack {
                ObservationPatternsDashboard()
                    .navigationTitle("Observation Patterns")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingPatterns = false }
                        }
                    }
            }
            #if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .sheet(isPresented: $viewModel.showingStudentPicker) {
            studentPickerSheet
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Student selector
                studentSelectorRow
                    .padding(.horizontal)
                    .padding(.top, 12)

                // Timer
                HStack {
                    Spacer()
                    ObservationTimerView(
                        elapsedSeconds: viewModel.elapsedSeconds,
                        isRunning: viewModel.isTimerRunning,
                        onToggle: { viewModel.toggleTimer() }
                    )
                    Spacer()
                }

                // Prompt card
                if let prompt = viewModel.currentPrompt {
                    ObservationPromptCard(
                        prompt: prompt,
                        onPrevious: { withAnimation { viewModel.previousPrompt() } },
                        onNext: { withAnimation { viewModel.nextPrompt() } }
                    )
                    .padding(.horizontal)
                }

                // Text editor
                observationTextEditor
                    .padding(.horizontal)

                // Quick-tag bar
                ObservationQuickTagBar(selectedTags: $viewModel.tags)
                    .padding(.horizontal)

                // Save button
                saveButton
                    .padding(.horizontal)
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Student Selector

    private var studentSelectorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OBSERVING")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .tracking(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.selectedStudents) { student in
                        studentChip(student)
                    }

                    // Add student button
                    Button {
                        viewModel.showingStudentPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.caption2)
                            if viewModel.selectedStudentIDs.isEmpty {
                                Text("Add Student")
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(dash: [4, 3]))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func studentChip(_ student: Student) -> some View {
        HStack(spacing: 4) {
            Text("\(student.firstName.prefix(1))\(student.lastName.prefix(1))")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(AppColors.color(forLevel: student.level).gradient, in: Circle())

            Text(student.firstName)
                .font(.caption)
                .fontWeight(.medium)

            Button {
                viewModel.selectedStudentIDs.remove(student.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        )
    }

    // MARK: - Text Editor

    private var observationTextEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OBSERVATION")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .tracking(0.5)

            TextEditor(text: $viewModel.bodyText)
                .font(.body)
                .frame(minHeight: 120)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CardStyle.cardBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(CardStyle.strokeOpacity))
                )
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            viewModel.saveObservation(context: modelContext)
        } label: {
            HStack(spacing: 8) {
                if viewModel.isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text("Save Observation")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(viewModel.canSave ? Color.accentColor : Color.gray.opacity(0.3))
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSave || viewModel.isSaving)
    }

}
