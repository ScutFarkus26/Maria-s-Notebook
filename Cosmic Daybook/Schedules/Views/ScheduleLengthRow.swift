// ScheduleLengthRow.swift
// The Schedules block sheet's Length row: the length in 5-minute steps and
// when the block ends ("30 min · ends 10:20"), so an entry can be checked
// against a paper schedule that gives ranges.

import SwiftUI

/// The sheet's Length stepper. A stepper shows no value of its own, so its
/// label carries the length and when the block ends.
struct ScheduleLengthRow: View {
    @Binding var length: Int
    let startMinute: Int

    var body: some View {
        Stepper {
            LabeledContent("Length", value: ScheduleBlockSheet.lengthRowText(startMinute: startMinute, length: length))
        } onIncrement: {
            length = ScheduleBlockSheet.stepped(length, by: 1)
        } onDecrement: {
            length = ScheduleBlockSheet.stepped(length, by: -1)
        }
    }
}

extension ScheduleBlockSheet {

    /// The Length row: "30 min · ends 10:20", so an entry can be checked
    /// against a paper schedule that gives ranges.
    static func lengthRowText(startMinute: Int, length: Int) -> String {
        "\(lengthText(length)) · ends \(TimetableDay.clockText(startMinute + length))"
    }
}
