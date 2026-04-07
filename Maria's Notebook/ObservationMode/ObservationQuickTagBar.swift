// ObservationQuickTagBar.swift
// Quick-tag capsule buttons for Montessori observation tags.
// Each button toggles a tag on/off in the observation.

import SwiftUI

struct ObservationQuickTagBar: View {
    @Binding var selectedTags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Observation tags section
            observationTagsSection

            // AMI curriculum domain tags
            curriculumDomainSection

            // Developmental characteristics section (Feature #9)
            developmentalTraitsSection
        }
    }

    // MARK: - Observation Tags

    private var observationTagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Observation Tags")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            FlowLayout(spacing: 6) {
                ForEach(MontessoriObservationTags.allTags, id: \.self) { tag in
                    quickTagButton(tag)
                }
            }
        }
    }

    // MARK: - Curriculum Domains

    private var curriculumDomainSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Curriculum Domains")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            FlowLayout(spacing: 6) {
                ForEach(MontessoriObservationTags.curriculumDomainTags, id: \.self) { tag in
                    quickTagButton(tag)
                }
            }
        }
    }

    // MARK: - Developmental Characteristics

    private var developmentalTraitsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Developmental Characteristics")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            FlowLayout(spacing: 6) {
                ForEach(DevelopmentalCharacteristic.allCases) { characteristic in
                    quickTagButton(characteristic.tag)
                }
            }
        }
    }

    // MARK: - Quick Tag Button

    private func quickTagButton(_ tag: String) -> some View {
        let parsed = TagHelper.parseTag(tag)
        let isSelected = selectedTags.contains(tag)

        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                if isSelected {
                    selectedTags.removeAll { $0 == tag }
                } else {
                    selectedTags.append(tag)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(parsed.color.color)
                    .frame(width: 6, height: 6)
                Text(parsed.name)
                    .font(.caption2)
                    .fontWeight(isSelected ? .semibold : .medium)
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? parsed.color.color : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
            }
        }
        .buttonStyle(.plain)
    }
}
