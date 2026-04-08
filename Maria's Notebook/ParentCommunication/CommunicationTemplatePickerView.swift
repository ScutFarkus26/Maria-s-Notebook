// CommunicationTemplatePickerView.swift
// Displays available communication templates (built-in and custom).

import SwiftUI

struct CommunicationTemplatePickerView: View {
    var isStandalone: Bool = false

    var body: some View {
        List {
            Section("Built-In Templates") {
                ForEach(CommunicationType.allCases) { type in
                    HStack(spacing: 12) {
                        Image(systemName: type.icon)
                            .font(.title3)
                            .foregroundStyle(type.color)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text(templateDescription(for: type))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if isStandalone {
                Section {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("Select a template when creating a new communication to auto-fill the body.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func templateDescription(for type: CommunicationType) -> String {
        switch type {
        case .conference: return "Structured notes for parent-teacher conferences"
        case .progressUpdate: return "Share recent classroom progress and highlights"
        case .concern: return "Address observations that need discussion"
        case .introduction: return "Welcome message for new families"
        case .endOfYear: return "Year-end reflections and summer recommendations"
        case .custom: return "Start from a blank template"
        }
    }
}
