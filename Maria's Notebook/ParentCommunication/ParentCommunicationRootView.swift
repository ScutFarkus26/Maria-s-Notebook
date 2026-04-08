// ParentCommunicationRootView.swift
// Hub view for parent communications with tabs for Drafts, Sent, and Templates.

import SwiftUI
import CoreData

struct ParentCommunicationRootView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel = ParentCommunicationViewModel()
    @State private var showingDraftSheet = false
    @State private var selectedCommunication: CDParentCommunication?

    // Change detection
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDParentCommunication.id, ascending: true)]
    ) private var allCommunications: FetchedResults<CDParentCommunication>

    private var changeToken: Int { allCommunications.count }

    var body: some View {
        content
            .navigationTitle("Parent Communication")
            .searchable(text: $viewModel.searchText, prompt: "Search communications")
            .onAppear { viewModel.loadData(context: viewContext) }
            .onChange(of: changeToken) { _, _ in viewModel.loadData(context: viewContext) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingDraftSheet = true
                    } label: {
                        Label("New Communication", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingDraftSheet) {
                NavigationStack {
                    CommunicationDraftView(viewModel: viewModel)
                }
            }
            .sheet(item: $selectedCommunication) { comm in
                NavigationStack {
                    CommunicationEditorSheet(communication: comm, viewModel: viewModel)
                }
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                // Tab picker
                Picker("Tab", selection: $viewModel.selectedTab) {
                    ForEach(CommunicationTab.allCases) { tab in
                        Text(tab.displayName).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // Tab content
                switch viewModel.selectedTab {
                case .drafts:
                    draftsTab
                case .sent:
                    sentTab
                case .templates:
                    templatesTab
                }
            }
        }
    }

    // MARK: - Drafts Tab

    private var draftsTab: some View {
        Group {
            if viewModel.drafts.isEmpty {
                ContentUnavailableView {
                    Label("No Drafts", systemImage: "envelope.badge")
                } description: {
                    Text("Tap + to create a new parent communication.")
                }
            } else {
                List {
                    ForEach(viewModel.drafts, id: \.id) { comm in
                        communicationRow(comm)
                            .onTapGesture { selectedCommunication = comm }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            viewModel.deleteCommunication(viewModel.drafts[index], context: viewContext)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sent Tab

    private var sentTab: some View {
        Group {
            if viewModel.sent.isEmpty {
                ContentUnavailableView {
                    Label("No Sent Communications", systemImage: "paperplane")
                } description: {
                    Text("Communications you mark as sent will appear here.")
                }
            } else {
                CommunicationLogView(viewModel: viewModel, onSelect: { selectedCommunication = $0 })
            }
        }
    }

    // MARK: - Templates Tab

    private var templatesTab: some View {
        CommunicationTemplatePickerView(isStandalone: true)
    }

    // MARK: - Row

    private func communicationRow(_ comm: CDParentCommunication) -> some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: comm.communicationType.icon)
                .font(.title3)
                .foregroundStyle(comm.communicationType.color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(comm.subject.isEmpty ? "Untitled" : comm.subject)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 6) {
                    Text(viewModel.studentName(for: comm))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.quaternary)

                    Text(comm.communicationType.displayName)
                        .font(.caption)
                        .foregroundStyle(comm.communicationType.color)
                }

                if let date = comm.modifiedAt {
                    Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if comm.isDraft {
                Text("Draft")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.orange.opacity(UIConstants.OpacityConstants.light))
                    )
            }
        }
        .contentShape(Rectangle())
    }
}
