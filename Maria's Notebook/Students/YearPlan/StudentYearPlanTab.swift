import SwiftUI
import CoreData

struct StudentYearPlanTab: View {
    let student: CDStudent

    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel = StudentYearPlanViewModel()
    @State private var nonSchoolCells: Set<CellID> = []
    @State private var showAddSequenceSheet = false
    @State private var popoverCellID: CellID?

    private var schoolYearRange: ClosedRange<Int> {
        let cal = AppCalendar.shared
        let now = Date()
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        // Aug or later: this year to next year. Before Aug: last year to this year.
        if month >= 8 {
            return year...(year + 1)
        } else {
            return (year - 1)...year
        }
    }

    var body: some View {
        CalendarGridView(
            title: "Year Plan",
            columnWidth: 190,
            yearRange: schoolYearRange,
            nonSchoolCells: nonSchoolCells,
            headerTrailing: {
                HStack(spacing: 12) {
                    if viewModel.behindPaceCount > 0 {
                        Button {
                            Task {
                                guard let id = student.id else { return }
                                await viewModel.readjust(studentID: id, context: viewContext)
                            }
                        } label: {
                            Label("Readjust", systemImage: "arrow.right.to.line")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.orange)
                    }

                    Button {
                        showAddSequenceSheet = true
                    } label: {
                        Label("Add Sequence", systemImage: "plus.circle")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .padding(.trailing, 8)
                }
            },
            dayContent: { cellID, isToday, isNonSchool in
                YearPlanDayCell(
                    cellID: cellID,
                    isToday: isToday,
                    isNonSchool: isNonSchool,
                    items: viewModel.items(for: cellID),
                    lessonsByID: viewModel.lessonsByID,
                    onDrop: { entryID, targetCellID in
                        handleEntryDrop(entryID: entryID, targetCellID: targetCellID)
                    },
                    popoverCellID: $popoverCellID
                )
                .popover(isPresented: popoverBinding(for: cellID)) {
                    DayDetailPopover(
                        cellID: cellID,
                        items: viewModel.items(for: cellID),
                        lessonsByID: viewModel.lessonsByID,
                        onRemove: { entry in
                            viewModel.removeEntry(entry, context: viewContext)
                            viewModel.load(studentID: student.id, context: viewContext)
                            popoverCellID = nil
                        },
                        onReschedule: { entry, newDate in
                            guard let studentID = student.id else { return }
                            Task {
                                await viewModel.rescheduleWithCascade(
                                    entry, to: newDate, studentID: studentID, context: viewContext
                                )
                            }
                            popoverCellID = nil
                        }
                    )
                }
            }
        )
        .task {
            viewModel.load(studentID: student.id, context: viewContext)
            await loadNonSchoolDays()
        }
        .sheet(isPresented: $showAddSequenceSheet) {
            AddSequenceSheet(student: student) {
                viewModel.load(studentID: student.id, context: viewContext)
            }
        }
    }

    private func popoverBinding(for cellID: CellID) -> Binding<Bool> {
        Binding(
            get: { popoverCellID == cellID },
            set: { isPresented in
                if !isPresented { popoverCellID = nil }
            }
        )
    }

    private func handleEntryDrop(entryID: UUID, targetCellID: CellID) {
        guard let entry = viewModel.entry(byID: entryID),
              entry.isPlanned,
              let studentID = student.id else { return }

        var comps = DateComponents()
        comps.year = targetCellID.year
        comps.month = targetCellID.month
        comps.day = targetCellID.day
        guard let targetDate = AppCalendar.shared.date(from: comps) else { return }

        Task {
            await viewModel.rescheduleWithCascade(
                entry, to: targetDate, studentID: studentID, context: viewContext
            )
        }
    }

    private func loadNonSchoolDays() async {
        let cal = AppCalendar.shared
        let range = schoolYearRange
        var startComps = DateComponents()
        startComps.year = range.lowerBound
        startComps.month = 8
        startComps.day = 1
        var endComps = DateComponents()
        endComps.year = range.upperBound
        endComps.month = 8
        endComps.day = 1
        guard let start = cal.date(from: startComps),
              let end = cal.date(from: endComps) else { return }

        let dates = await SchoolCalendar.nonSchoolDays(in: start..<end, using: viewContext)
        var cells = Set<CellID>()
        for date in dates {
            cells.insert(CellID(
                year: cal.component(.year, from: date),
                month: cal.component(.month, from: date),
                day: cal.component(.day, from: date)
            ))
        }
        nonSchoolCells = cells
    }
}
