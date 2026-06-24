// TodayViewHeader.swift
// Header and attendance strip components for TodayView - extracted for maintainability

import SwiftUI
import CoreData

// MARK: - TodayView Header Extension

extension TodayView {

    // MARK: - Header (macOS)

    var header: some View {
        ViewHeader(title: "Today") {
            HStack(spacing: 16) {
                // Date navigation
                HStack(spacing: 8) {
                    Button {
                        let prev = previousSchoolDaySync(before: viewModel.date)
                        viewModel.date = AppCalendar.startOfDay(prev)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    DatePicker("Date", selection: Binding(get: { viewModel.date }, set: { newValue in
                        let coerced = nearestSchoolDaySync(to: newValue)
                        viewModel.date = AppCalendar.startOfDay(coerced)
                    }), displayedComponents: .date)
                    #if os(macOS)
                    .datePickerStyle(.field)
                    #else
                    .datePickerStyle(.compact)
                    #endif
                    .labelsHidden()

                    Button {
                        let next = nextSchoolDaySync(after: viewModel.date)
                        viewModel.date = AppCalendar.startOfDay(next)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    if !Calendar.current.isDateInToday(viewModel.date) {
                        Button {
                            let today = Date()
                            let coerced = nearestSchoolDaySync(to: today)
                            viewModel.date = AppCalendar.startOfDay(coerced)
                        } label: {
                            Text("Today")
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Attendance Strip

    var attendanceStrip: some View {
        Button {
            adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isAttendanceExpanded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                // Primary stat: In Class (Present + Tardy)
                HStack(spacing: 8) {
                    Text("In Class")
                        .font(AppTheme.ScaledFont.calloutSemibold)
                        .foregroundStyle(.secondary)
                    Text("\(viewModel.attendanceSummary.presentCount)")
                        .font(AppTheme.ScaledFont.titleSmall)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(Color.accentColor.opacity(UIConstants.OpacityConstants.medium))
                        )
                }
                .fixedSize()

                if viewModel.attendanceSummary.tardyCount > 0 {
                    statChip(title: "Tardy", count: viewModel.attendanceSummary.tardyCount, color: .blue)
                        .fixedSize()
                }
                if viewModel.attendanceSummary.absentCount > 0 {
                    statChip(title: "Absent", count: viewModel.attendanceSummary.absentCount, color: .red)
                        .fixedSize()
                }
                if viewModel.attendanceSummary.leftEarlyCount > 0 {
                    statChip(title: "Left Early", count: viewModel.attendanceSummary.leftEarlyCount, color: .purple)
                        .fixedSize()
                }

                if !(viewModel.absentToday.isEmpty && viewModel.leftEarlyToday.isEmpty) {
                    // Resolve names once per student — sort key and display label are the same value.
                    let absentPairs = viewModel.absentToday
                        .map { (id: $0, name: displayNameForID($0)) }
                        .filter { !$0.name.trimmed().isEmpty }
                        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    let leftEarlyPairs = viewModel.leftEarlyToday
                        .map { (id: $0, name: displayNameForID($0)) }
                        .filter { !$0.name.trimmed().isEmpty }
                        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(absentPairs, id: \.id) { pair in
                                studentPill(pair.name, color: .red)
                                    .contextMenu {
                                        Text(pair.name)
                                        Divider()
                                        Button {
                                            markTardy(pair.id)
                                        } label: {
                                            Label("Mark Tardy", systemImage: "clock")
                                        }
                                    }
                            }
                            if !absentPairs.isEmpty && !leftEarlyPairs.isEmpty {
                                Color.clear.frame(width: 8)
                            }
                            ForEach(leftEarlyPairs, id: \.id) { pair in
                                studentPill(pair.name, color: .purple)
                            }
                        }
                        .padding(.leading, 8)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isAttendanceExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(UIConstants.OpacityConstants.hint))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stat Chip

    func statChip(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(title) \(count)")
                .font(AppTheme.ScaledFont.captionSmallSemibold)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().strokeBorder(color.opacity(0.20), lineWidth: 1))
    }

    // MARK: - CDStudent Pill

    @ViewBuilder
    func studentPill(_ name: String, color: Color) -> some View {
        Text(name)
            .font(AppTheme.ScaledFont.captionSmallSemibold)
            .foregroundStyle(color)
            .textSelection(.disabled)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(UIConstants.OpacityConstants.medium)))
    }
}
