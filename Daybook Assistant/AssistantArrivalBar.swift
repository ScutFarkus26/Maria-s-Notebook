import SwiftUI

/// The bar under the grid: the count (or the Undo for closing arrival), the
/// arrival control, and the iCloud line.
///
/// Closing arrival marks everyone still unmarked absent, so it's a button
/// that asks first, naming exactly who, not a switch. On 2026-09-29 a tap
/// aimed at a half-hidden bottom tile landed on the old Late pill and marked
/// nineteen children absent at once. The question doubles as a last look at
/// who's missing. After closing, a "Late" capsule says what a tap now does,
/// and its menu reopens arrival.
struct AssistantArrivalBar: View {
    let viewModel: AssistantAttendanceViewModel
    let coreDataStack: CoreDataStack
    /// "Marked 4 absent · Undo", in the count's place until the next mark.
    @Binding var undo: ArrivalUndo?

    @State private var confirmingClose = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Side by side normally; stacked at accessibility sizes, where the count
    /// and the button won't both fit on one line.
    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewModel.dayOff == nil, !viewModel.rows.isEmpty {
                rowLayout {
                    countOrUndo
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    arrivalControl
                }
                .frame(minHeight: 32)
            }
            AssistantSyncStatusView(coreDataStack: coreDataStack)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.phase)
        .confirmationDialog(closeTitle, isPresented: $confirmingClose, titleVisibility: .visible) {
            Button("Mark \(unmarkedNames.count) Absent", role: .destructive, action: closeArrival)
        } message: {
            Text("\(unmarkedNames.formatted(.list(type: .and))). After this, a tap marks a child late.")
        }
    }

    // MARK: - Pieces

    private var countOrUndo: some View {
        Group {
            if let undo {
                HStack(spacing: 12) {
                    Text("Marked \(undo.count) absent")
                    Button("Undo") {
                        withAnimation(.smooth(duration: 0.3)) {
                            viewModel.returnToArrival(undo: true)
                            self.undo = nil
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                }
                .transition(.opacity)
            } else {
                Text(AssistantAttendanceViewModel.tally(viewModel.rows))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.smooth, value: AssistantAttendanceViewModel.tally(viewModel.rows))
                    .transition(.opacity)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .animation(.smooth(duration: 0.3), value: undo?.id)
    }

    /// Close Arrival while anyone's unmarked; "Late" once closed. Nothing
    /// ahead of the day (there's no arrival yet) or on a locked day.
    @ViewBuilder
    private var arrivalControl: some View {
        if viewModel.canMark, !viewModel.isFuture {
            switch viewModel.phase {
            case .arrival:
                if !unmarkedNames.isEmpty {
                    Button("Close Arrival…") { confirmingClose = true }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .accessibilityHint("Asks before marking everyone not here yet absent")
                }
            case .late:
                Menu {
                    Button("Reopen Arrival", systemImage: "arrow.uturn.backward") {
                        withAnimation(.smooth(duration: 0.3)) {
                            viewModel.returnToArrival()
                            undo = nil
                        }
                    }
                } label: {
                    Label("Late", systemImage: "clock.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.14), in: Capsule())
                        .foregroundStyle(.blue)
                }
                .accessibilityLabel("Arrival closed: a tap marks late")
                .accessibilityHint("Opens Reopen Arrival")
            }
        }
    }

    // MARK: - Closing

    private var unmarkedNames: [String] {
        viewModel.rows.filter { $0.status == .unmarked }.map(\.shortName)
    }

    private var closeTitle: String {
        unmarkedNames.count == 1 ? "Mark 1 child absent?" : "Mark \(unmarkedNames.count) children absent?"
    }

    private func closeArrival() {
        withAnimation(.smooth(duration: 0.3)) {
            let count = viewModel.beginLate()
            undo = count > 0 ? ArrivalUndo(count: count) : nil
        }
    }
}

/// The Undo offered after closing arrival.
struct ArrivalUndo: Equatable {
    let id = UUID()
    let count: Int
}
