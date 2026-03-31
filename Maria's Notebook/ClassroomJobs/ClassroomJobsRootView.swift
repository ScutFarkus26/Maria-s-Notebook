// ClassroomJobsRootView.swift
// Main view for the Classroom Job Rotation Board.

import SwiftUI
import CoreData

struct ClassroomJobsRootView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel = ClassroomJobsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Week of")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.weekDisplayString)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Spacer()

                Button {
                    viewModel.rotateJobs(context: viewContext)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                        Text("Rotate")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.jobs.filter(\.isActive).isEmpty)

                Button {
                    viewModel.editingJob = nil
                    viewModel.showingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .padding()

            Divider()

            if viewModel.jobs.isEmpty {
                ContentUnavailableView(
                    "No Classroom Jobs",
                    systemImage: "person.2.badge.gearshape",
                    description: Text("Create jobs like Line Leader, Plant Caretaker, or Table Washer to get started.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.jobs, id: \.objectID) { job in
                            ClassroomJobCard(
                                job: job,
                                assignments: job.id.flatMap { viewModel.currentAssignments[$0] } ?? [],
                                viewModel: viewModel,
                                viewContext: viewContext
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Jobs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.showingHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
        }
        .sheet(isPresented: $viewModel.showingEditor) {
            ClassroomJobEditorSheet(
                existingJob: viewModel.editingJob,
                viewModel: viewModel,
                viewContext: viewContext
            )
        }
        .sheet(isPresented: $viewModel.showingHistory) {
            NavigationStack {
                ClassroomJobHistoryView()
                    .navigationTitle("Job History")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { viewModel.showingHistory = false }
                        }
                    }
            }
            #if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .onAppear { viewModel.loadData(context: viewContext) }
    }
}
