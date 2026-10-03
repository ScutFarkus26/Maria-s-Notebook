//
//  SinglesRow.swift
//  Cosmic Daybook
//
//  The lessons only one child is ready for, folded into one row on the
//  Groups page ("N lessons with one child ready") so they never crowd out
//  the groups. It expands in place: each lesson with its breadcrumb, the
//  child and her wait, and Plan.
//

import SwiftUI

struct SinglesRow: View {
    let singles: [LessonGroup]
    let palette: StudentAgePalette
    @Binding var isExpanded: Bool
    let onPlan: (LessonGroup) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                #if os(iOS)
                .frame(minHeight: 44)
                #endif
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                ForEach(singles) { single in
                    Divider()
                    row(single)
                        .padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var title: String {
        singles.count == 1 ? "1 lesson with one child ready" : "\(singles.count) lessons with one child ready"
    }

    private func row(_ single: LessonGroup) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(single.lessonName)
                        .font(.subheadline.weight(.medium))
                    Text(single.stepLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                GroupBreadcrumb(area: single.area, sequence: single.sequence)
                ForEach(single.ready) { member in
                    GroupMemberRow(member: member, palette: palette)
                }
            }
            // Full width, so the child's wait lines up at the right as on the cards.
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Plan") { onPlan(single) }
                .buttonStyle(.bordered)
                #if os(iOS)
                .frame(minHeight: 44)
                #endif
                .accessibilityLabel("Plan \(single.lessonName)")
        }
    }
}
