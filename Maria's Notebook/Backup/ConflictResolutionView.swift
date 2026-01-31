// ConflictResolutionView.swift
// UI for reviewing and resolving merge conflicts during backup restore

import SwiftUI

/// View for reviewing and resolving conflicts during merge restore
struct ConflictResolutionView: View {
    let analysis: ConflictResolutionService.ConflictAnalysis
    @Binding var conflicts: [ConflictResolutionService.Conflict]
    let onApply: () -> Void
    let onCancel: () -> Void

    @State private var selectedStrategy: ConflictResolutionService.ConflictStrategy = .newerWins
    @State private var expandedConflictIDs: Set<UUID> = []
    @State private var filterEntityType: String? = nil

    private var groupedConflicts: [String: [ConflictResolutionService.Conflict]] {
        conflicts.grouped(by: { $0.entityType })
    }

    private var entityTypes: [String] {
        Array(Set(conflicts.map { $0.entityType })).sorted()
    }

    private var filteredConflicts: [ConflictResolutionService.Conflict] {
        if let filter = filterEntityType {
            return conflicts.filter { $0.entityType == filter }
        }
        return conflicts
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Strategy Selection
            strategySelectionView

            Divider()

            // Conflicts List
            if conflicts.isEmpty {
                noConflictsView
            } else {
                conflictListView
            }

            Divider()

            // Footer with actions
            footerView
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title2)
                Text("Resolve Conflicts")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(conflicts.count) conflicts found")
                    .foregroundStyle(.secondary)
            }

            Text("The following records exist in both your database and the backup. Choose how to handle each conflict.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Strategy Selection

    private var strategySelectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Resolution Strategy")
                .font(.headline)

            Picker("Strategy", selection: $selectedStrategy) {
                ForEach(ConflictResolutionService.ConflictStrategy.allCases) { strategy in
                    Text(strategy.rawValue).tag(strategy)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedStrategy) { _, newStrategy in
                applyStrategy(newStrategy)
            }

            Text(selectedStrategy.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - No Conflicts View

    private var noConflictsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("No Conflicts")
                .font(.title3)
                .fontWeight(.medium)
            Text("All records from the backup can be imported without conflicts.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Conflict List

    private var conflictListView: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack {
                Text("Filter:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Entity Type", selection: $filterEntityType) {
                    Text("All Types").tag(nil as String?)
                    ForEach(entityTypes, id: \.self) { type in
                        Text(type).tag(type as String?)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                // Bulk actions
                Menu {
                    Button("Keep All Local") {
                        applyBulkResolution(.keepLocal)
                    }
                    Button("Use All Backup") {
                        applyBulkResolution(.useBackup)
                    }
                } label: {
                    Label("Bulk Actions", systemImage: "ellipsis.circle")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Conflict list
            List {
                ForEach(filteredConflicts) { conflict in
                    conflictRow(conflict)
                }
            }
            .listStyle(.plain)
        }
    }

    private func conflictRow(_ conflict: ConflictResolutionService.Conflict) -> some View {
        let index = conflicts.firstIndex(where: { $0.id == conflict.id })!
        let isExpanded = expandedConflictIDs.contains(conflict.id)

        return VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                // Entity type badge
                Text(conflict.entityType)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundColor(.accentColor)
                    .clipShape(Capsule())

                // Entity description
                VStack(alignment: .leading, spacing: 2) {
                    Text(conflict.localSummary)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if let backupDate = conflict.backupUpdatedAt {
                        Text("Backup: \(backupDate, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Resolution picker
                Picker("Resolution", selection: $conflicts[index].resolution) {
                    ForEach(ConflictResolutionService.ConflictResolution.allCases, id: \.self) { resolution in
                        Label(resolution.rawValue, systemImage: resolution == .keepLocal ? "square.and.arrow.down" : "arrow.up.doc")
                            .tag(resolution)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)

                // Expand button
                Button {
                    withAnimation {
                        if isExpanded {
                            expandedConflictIDs.remove(conflict.id)
                        } else {
                            expandedConflictIDs.insert(conflict.id)
                        }
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Expanded details
            if isExpanded {
                HStack(spacing: 16) {
                    // Local version
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "laptopcomputer")
                                .foregroundStyle(.secondary)
                            Text("Current Version")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        Text(conflict.localSummary)
                            .font(.caption)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        if let date = conflict.localUpdatedAt {
                            Text("Updated: \(date.formatted())")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Backup version
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "arrow.down.doc")
                                .foregroundStyle(.secondary)
                            Text("Backup Version")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        Text(conflict.backupSummary)
                            .font(.caption)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        if let date = conflict.backupUpdatedAt {
                            Text("Updated: \(date.formatted())")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            // Summary
            VStack(alignment: .leading, spacing: 2) {
                let keepLocalCount = conflicts.filter { $0.resolution == .keepLocal }.count
                let useBackupCount = conflicts.filter { $0.resolution == .useBackup }.count

                Text("Summary:")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 16) {
                    Label("\(keepLocalCount) keep local", systemImage: "laptopcomputer")
                    Label("\(useBackupCount) use backup", systemImage: "arrow.down.doc")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.bordered)

            Button("Apply Resolutions") {
                onApply()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Actions

    private func applyStrategy(_ strategy: ConflictResolutionService.ConflictStrategy) {
        for i in conflicts.indices {
            switch strategy {
            case .skipExisting, .keepLocal:
                conflicts[i].resolution = .keepLocal
            case .useBackup:
                conflicts[i].resolution = .useBackup
            case .newerWins:
                conflicts[i].resolution = conflicts[i].recommendedResolution
            case .manual:
                conflicts[i].resolution = conflicts[i].recommendedResolution
            }
        }
    }

    private func applyBulkResolution(_ resolution: ConflictResolutionService.ConflictResolution) {
        for i in conflicts.indices {
            if filterEntityType == nil || conflicts[i].entityType == filterEntityType {
                conflicts[i].resolution = resolution
            }
        }
    }
}

// MARK: - Summary View for Conflict Stats

struct ConflictSummaryView: View {
    let analysis: ConflictResolutionService.ConflictAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: analysis.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(analysis.isEmpty ? .green : .orange)
                Text(analysis.isEmpty ? "No Conflicts" : "\(analysis.totalConflicts) Conflicts Found")
                    .font(.headline)
            }

            if !analysis.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    let grouped = analysis.conflicts.grouped(by: { $0.entityType })
                    ForEach(grouped.keys.sorted(), id: \.self) { entityType in
                        HStack {
                            Text(entityType)
                                .font(.subheadline)
                            Spacer()
                            Text("\(grouped[entityType]?.count ?? 0)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(analysis.isEmpty ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
        )
    }
}
