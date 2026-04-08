// CommunicationLogView.swift
// List of sent communications grouped by month.

import SwiftUI

struct CommunicationLogView: View {
    @Bindable var viewModel: ParentCommunicationViewModel
    var onSelect: (CDParentCommunication) -> Void

    var body: some View {
        List {
            ForEach(viewModel.sentGroupedByMonth, id: \.key) { month, communications in
                Section(month) {
                    ForEach(communications, id: \.id) { comm in
                        sentRow(comm)
                            .onTapGesture { onSelect(comm) }
                    }
                }
            }
        }
    }

    private func sentRow(_ comm: CDParentCommunication) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "paperplane.fill")
                .font(.caption)
                .foregroundStyle(comm.communicationType.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(comm.subject.isEmpty ? "Untitled" : comm.subject)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 6) {
                    Text(viewModel.studentName(for: comm))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let sentAt = comm.sentAt {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                        Text(sentAt, format: .dateTime.month(.abbreviated).day())
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Text(comm.communicationType.displayName)
                .font(.caption2)
                .foregroundStyle(comm.communicationType.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(comm.communicationType.color.opacity(UIConstants.OpacityConstants.light))
                )
        }
        .contentShape(Rectangle())
    }
}
