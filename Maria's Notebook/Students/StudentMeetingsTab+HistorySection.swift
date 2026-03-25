// StudentMeetingsTab+HistorySection.swift
// Meeting history section and editing functionality

import SwiftUI
import SwiftData

extension StudentMeetingsTab {

    var historySection: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Meeting History")
                    .font(.headline)
                    .foregroundStyle(.primary)

                if meetingItems.isEmpty {
                    Text("No prior meetings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(meetingItems) { item in
                            let isExpanded = expandedHistoryIDs.contains(item.id)
                            VStack(alignment: .leading, spacing: 0) {
                                // Header (always visible)
                                HStack(spacing: 8) {
                                    Text(DateFormatters.mediumDate.string(from: item.date))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if item.completed {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AppColors.success)
                                    }
                                    Text("\u{2022}")
                                        .foregroundStyle(.secondary)

                                    // Summary with AI indicator
                                    HStack(spacing: 4) {
                                        if let summary = meetingSummaries[item.id] {
                                            // Show sparkle only if AI actually generated it
                                            if aiGeneratedSummaries.contains(item.id) {
                                                Image(systemName: "sparkles")
                                                    .foregroundStyle(.purple)
                                                    .font(.caption2)
                                            }
                                            Text(summary)
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                        } else if generatingSummaries.contains(item.id) {
                                            ProgressView()
                                                .controlSize(.mini)
                                            Text("Summarizing...")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text(summaryText(for: item))
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                        }
                                    }

                                    Spacer()
                                    Menu {
                                        Button("Edit", systemImage: "square.and.pencil") { beginEdit(item) }
                                        Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
                                    } label: {
                                        Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    adaptiveWithAnimation {
                                        if isExpanded {
                                            expandedHistoryIDs.remove(item.id)
                                        } else {
                                            expandedHistoryIDs.insert(item.id)
                                        }
                                    }
                                }

                                // Expanded content
                                if isExpanded {
                                    VStack(alignment: .leading, spacing: 6) {
                                        historyDetailLine(title: "Reflection", text: item.reflection)
                                        historyDetailLine(title: "Focus", text: item.focus)
                                        historyDetailLine(title: "Requests", text: item.requests)
                                        if !item.guideNotes.trimmed().isEmpty {
                                            historyDetailLine(title: "Guide notes", text: item.guideNotes)
                                        }
                                    }
                                    .padding(.top, 8)
                                }
                            }
                            .task {
                                // Generate summary when meeting appears
                                if meetingSummaries[item.id] == nil && !generatingSummaries.contains(item.id) {
                                    await generateSummary(for: item)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }
}
