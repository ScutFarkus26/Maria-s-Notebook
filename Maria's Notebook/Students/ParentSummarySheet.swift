//
//  ParentSummarySheet.swift
//  Maria's Notebook
//
//  Sheet for displaying and sharing AI-generated parent summaries
//

import SwiftUI

// MARK: - Parent Summary Sheet

struct ParentSummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    let summary: String
    let student: Student

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Progress Summary for \(student.fullName)")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(summary)
                        .font(.body)
                        .lineSpacing(4)

                    Divider()

                    Text("This summary was generated using AI-powered analysis of classroom observations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Parent Summary")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: summary) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}
