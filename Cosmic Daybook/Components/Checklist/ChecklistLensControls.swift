//
//  ChecklistLensControls.swift
//  Cosmic Daybook
//
//  The controls that switch the checklist's lens: a segmented "All Marks / Ready to
//  Present (12)" in the Mac and iPad toolbar, and a menu in the iPhone's header. Plus
//  the iPhone's per-row Plan, which sits by the lesson's name because the phone has
//  no Class column.
//

import SwiftUI

/// The toolbar's segmented lens picker (Mac and iPad).
struct ChecklistLensPicker: View {
    @Binding var lens: ChecklistLens
    let readyCount: Int

    var body: some View {
        Picker("Show", selection: $lens) {
            ForEach(ChecklistLens.allCases) { lens in
                Text(lens.title(readyCount: readyCount)).tag(lens)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .help("Show every mark, or lift the children each lesson can be given to now")
    }
}

/// The iPhone header's lens menu: the same two choices, with a check on the current one.
struct ChecklistLensMenu: View {
    @Binding var lens: ChecklistLens
    let readyCount: Int

    var body: some View {
        Menu {
            Picker("Show", selection: $lens) {
                ForEach(ChecklistLens.allCases) { lens in
                    Text(lens.title(readyCount: readyCount)).tag(lens)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle" + (lens == .ready ? ".fill" : ""))
                .imageScale(.large)
        }
        .accessibilityLabel("Show")
        .accessibilityValue(lens.title(readyCount: readyCount))
    }
}

/// "Plan 5" at the end of a lesson's name on the iPhone, under the Ready lens.
struct ChecklistCompactPlanButton: View {
    let readyCount: Int
    let onPlan: () -> Void

    var body: some View {
        Button(action: onPlan) {
            Text("Plan \(readyCount)")
                .font(.caption.weight(.semibold).monospacedDigit())
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(.blue)
        .fixedSize()
        .accessibilityLabel("Plan for \(readyCount) ready")
    }
}
