// TransitionPlannerRootView.swift
// Main view for the Transition & Bridging Planner.

import SwiftUI
import SwiftData

struct TransitionPlannerRootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = TransitionPlannerViewModel()
    @State private var selectedPlan: TransitionPlan?

    var body: some View {
        VStack(spacing: 0) {
            // Status filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    PillButton(title: "All", isSelected: viewModel.selectedStatusFilter == nil) {
                        viewModel.selectedStatusFilter = nil
                    }
                    ForEach(TransitionStatus.allCases) { status in
                        PillButton(title: status.displayName, isSelected: viewModel.selectedStatusFilter == status) {
                            viewModel.selectedStatusFilter = viewModel.selectedStatusFilter == status ? nil : status
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)

            Divider()

            if viewModel.plans.isEmpty {
                ContentUnavailableView(
                    "No Transition Plans",
                    systemImage: "arrow.right.arrow.left",
                    description: Text("Create a transition plan to track a student's readiness for the next level.")
                )
            } else if viewModel.filteredPlans.isEmpty {
                ContentUnavailableView(
                    "No Matching Plans",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("No transition plans match the current filter.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.filteredPlans) { plan in
                            Button {
                                selectedPlan = plan
                            } label: {
                                TransitionPlanCard(plan: plan, viewModel: viewModel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Transitions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.showingNewPlanPicker = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(viewModel.availableStudents.isEmpty)
            }
        }
        .sheet(isPresented: $viewModel.showingNewPlanPicker) {
            studentPickerSheet
        }
        .sheet(item: $selectedPlan) { plan in
            NavigationStack {
                TransitionPlanDetailView(plan: plan, viewModel: viewModel)
            }
            #if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .onAppear { viewModel.loadData(context: modelContext) }
    }

    private var studentPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(viewModel.availableStudents) { student in
                    Button {
                        viewModel.createPlan(studentID: student.id, context: modelContext)
                        viewModel.showingNewPlanPicker = false
                    } label: {
                        HStack(spacing: 8) {
                            Text("\(student.firstName.prefix(1))\(student.lastName.prefix(1))")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(AppColors.color(forLevel: student.level).gradient, in: Circle())

                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(student.firstName) \(student.lastName)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                Text(student.level.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Select Student")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.showingNewPlanPicker = false }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        #endif
    }
}
