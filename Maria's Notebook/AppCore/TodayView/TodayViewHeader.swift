// TodayViewHeader.swift
// Header and attendance strip components for TodayView - extracted for maintainability

import SwiftUI
import SwiftData

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
                    .datePickerStyle(.field)
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

                // Level filter
                Picker("Level", selection: $viewModel.levelFilter) {
                    ForEach(TodayViewModel.LevelFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
        }
    }

    // MARK: - Attendance Strip

    var attendanceStrip: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isAttendanceExpanded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                // Primary stat: In Class (Present + Tardy)
                HStack(spacing: 8) {
                    Text("In Class")
                        .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(viewModel.attendanceSummary.presentCount)")
                        .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(Color.accentColor.opacity(0.12))
                        )
                }

                statChip(title: "Tardy", count: viewModel.attendanceSummary.tardyCount, color: .blue)
                statChip(title: "Absent", count: viewModel.attendanceSummary.absentCount, color: .red)
                statChip(title: "Left Early", count: viewModel.attendanceSummary.leftEarlyCount, color: .purple)

                if !(viewModel.absentToday.isEmpty && viewModel.leftEarlyToday.isEmpty) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(StringSorting.sortByLocalizedCaseInsensitive(items: viewModel.absentToday, extractor: { displayNameForID($0) }), id: \.self) { sid in
                                let name = displayNameForID(sid)
                                if !name.trimmed().isEmpty {
                                    studentPill(name, color: .red)
                                        .contextMenu {
                                            Text(name)
                                            Divider()
                                            Button {
                                                markTardy(sid)
                                            } label: {
                                                Label("Mark Tardy", systemImage: "clock")
                                            }
                                        }
                                }
                            }
                            if !viewModel.absentToday.isEmpty && !viewModel.leftEarlyToday.isEmpty {
                                Color.clear.frame(width: 8)
                            }
                            ForEach(StringSorting.sortByLocalizedCaseInsensitive(items: viewModel.leftEarlyToday, extractor: { displayNameForID($0) }), id: \.self) { sid in
                                let name = displayNameForID(sid)
                                if !name.trimmed().isEmpty {
                                    studentPill(name, color: .purple)
                                }
                            }
                        }
                        .padding(.leading, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isAttendanceExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stat Chip

    func statChip(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(title) \(count)")
                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().strokeBorder(color.opacity(0.20), lineWidth: 1))
    }

    // MARK: - Student Pill

    @ViewBuilder
    func studentPill(_ name: String, color: Color) -> some View {
        Text(name)
            .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .textSelection(.disabled)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}
