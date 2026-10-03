//
//  ChecklistSelectionBar.swift
//  Cosmic Daybook
//
//  The Mac and iPad's floating bar while cells are selected: how many and of which
//  lesson, Present as a group (one lesson only), Presented, Mastered, Add to Inbox,
//  More (Previously Presented, Add Work, Clear) and ✕. It replaces the old Select
//  mode's toolbar; the iPhone keeps that one.
//

import SwiftUI

enum ChecklistSelectionBarAction {
    case presentGroup
    case presented
    case mastered
    case addToInbox
    case previouslyPresented
    case addWork
    case clear
    case dismiss
}

struct ChecklistSelectionBar: View {
    let count: Int
    /// The lesson every selected cell shares; nil when the selection spans lessons.
    let lessonName: String?
    let perform: (ChecklistSelectionBarAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count) selected")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                Text(lessonName ?? "Several lessons")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: 200, alignment: .leading)
            .padding(.trailing, 6)

            if lessonName != nil {
                Button("Present as a Group…") { perform(.presentGroup) }
                    .buttonStyle(.borderedProminent)
                    .help("Open the present-a-lesson sheet for these children")
            }
            Button { perform(.presented) } label: {
                Label { Text("Presented") } icon: { ChecklistMark(status: .presented, size: 12) }
            }
            Button { perform(.mastered) } label: {
                Label { Text("Mastered") } icon: { ChecklistMark(status: .mastered, size: 12) }
            }
            Button("Add to Inbox") { perform(.addToInbox) }
            moreMenu
            Button { perform(.dismiss) } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Clear the selection")
            .accessibilityLabel("Clear selection")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(count) cells selected")
    }

    private var moreMenu: some View {
        Menu {
            Button { perform(.previouslyPresented) } label: {
                Label("Previously Presented", systemImage: "clock.badge.checkmark")
            }
            if lessonName != nil {
                Button { perform(.addWork) } label: {
                    Label("Add Work…", systemImage: "pencil.and.list.clipboard")
                }
            }
            Divider()
            Button(role: .destructive) { perform(.clear) } label: {
                Label("Clear", systemImage: "xmark.circle")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
        .accessibilityLabel("More actions")
    }
}
