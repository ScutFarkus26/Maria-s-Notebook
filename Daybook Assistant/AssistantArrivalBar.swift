import SwiftUI

/// The bar under the grid: the Undo for closing arrival, the arrival
/// control, the front-desk email, and the iCloud line. The lines are
/// centered; while the arrival control shows, its neighbor moves to the left
/// beside it. The day's count is at the top of the grid
/// (`AssistantClassCount`).
///
/// Closing arrival marks everyone still unmarked absent, so it's a button
/// that asks first, naming exactly who, not a switch. On 2026-09-29 a tap
/// aimed at a half-hidden bottom tile landed on the old Late pill and marked
/// nineteen children absent at once. The question doubles as a last look at
/// who's missing. After closing, an amber "Late" capsule says what a tap now
/// does, and its menu reopens arrival.
///
/// Its top edge fills green as children come in (gray for the absent), so
/// how close the class is shows without reading. A child back after days
/// away gets "Welcome back, Maya" beside the arrival control for a few
/// seconds; when everyone's marked it says so for a few seconds.
struct AssistantArrivalBar: View {
    let viewModel: AssistantAttendanceViewModel
    let coreDataStack: CoreDataStack
    /// "Marked 4 absent · Undo", beside the Late capsule until the next mark.
    @Binding var undo: ArrivalUndo?
    /// Email the Front Desk (and Send Again): opens the ready email.
    var onEmailFrontDesk: () -> Void = {}

    @State private var confirmingClose = false
    /// Set by Close Arrival & Email: once arrival closes, open the email.
    @State private var emailAfterClose = false
    /// "Everyone's here · 8:14", for a few seconds after the last mark.
    @State private var finishedLine: String?
    /// "Welcome back, Maya", for a few seconds after she marks them in.
    @State private var welcomeLine: String?
    /// Bumped at the moments the email falls due and goes late.
    @State private var dueTicks = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Side by side normally; stacked at accessibility sizes, where the count
    /// and the button won't both fit on one line.
    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    var body: some View {
        VStack(spacing: 6) {
            if viewModel.dayOff == nil, !viewModel.rows.isEmpty {
                let showsControl = showsArrivalControl && !emailClosesArrival
                if showsControl {
                    rowLayout {
                        // The button takes its width first; the line gets
                        // what's left, so it knows when to shorten.
                        barLine
                            .frame(maxWidth: .infinity, alignment: .leading)
                        arrivalControl
                            .fixedSize()
                    }
                    .frame(minHeight: 32)
                } else if hasBarLine {
                    barLine
                        .frame(minHeight: 32)
                }
            }
            AssistantFrontDeskRow(viewModel: viewModel, onSend: onEmailFrontDesk) {
                emailAfterClose = true
                confirmingClose = true
            }
            AssistantSyncStatusView(coreDataStack: coreDataStack)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
        .overlay(alignment: .top) { fillLine }
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.phase)
        .onChange(of: viewModel.completions) {
            finishedLine = AssistantAttendanceViewModel.completionText(
                viewModel.rows, at: viewModel.isToday ? Date() : nil, milestone: viewModel.milestone
            )
        }
        .task(id: finishedLine) {
            guard finishedLine != nil, (try? await Task.sleep(for: .seconds(5))) != nil else { return }
            finishedLine = nil
        }
        .onChange(of: viewModel.welcome) { _, welcome in
            welcomeLine = welcome.map { "Welcome back, \($0.name)" }
        }
        .task(id: welcomeLine) {
            guard welcomeLine != nil, (try? await Task.sleep(for: .seconds(3))) != nil else { return }
            welcomeLine = nil
        }
        .onChange(of: viewModel.date) {
            finishedLine = nil
            welcomeLine = nil
        }
        .task(id: viewModel.date) {
            // Redraws the bar as the email falls due and as it goes late.
            // A TimelineView around the row did this too, but the Close
            // Arrival question stopped appearing from a button inside one.
            for time in viewModel.frontDesk.changeTimes(on: viewModel.date) where time > Date() {
                guard (try? await Task.sleep(for: .seconds(time.timeIntervalSinceNow))) != nil else { return }
                dueTicks += 1
            }
        }
        .confirmationDialog(closeTitle, isPresented: $confirmingClose, titleVisibility: .visible) {
            if emailAfterClose {
                Button("Mark \(unmarkedNames.count) Absent & Email", role: .destructive) {
                    closeArrival()
                    onEmailFrontDesk()
                }
            }
            // From the email button too, for a day someone else sends it.
            Button("Mark \(unmarkedNames.count) Absent", role: .destructive) {
                closeArrival()
            }
        } message: {
            Text("\(unmarkedNames.formatted(.list(type: .and))). After this, a tap marks a child late.")
        }
        .onChange(of: confirmingClose) { _, showing in
            if !showing { emailAfterClose = false }
        }
    }

    // MARK: - Pieces

    /// Whether `barLine` has anything to say.
    private var hasBarLine: Bool {
        (undo != nil && viewModel.canMark) || welcomeLine != nil
            || (finishedLine != nil && viewModel.unmarkedCount == 0)
    }

    /// The Undo, a welcome back, or everyone being marked; nothing otherwise.
    private var barLine: some View {
        Group {
            if let undo, viewModel.canMark {
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
                .minimumScaleFactor(0.8)
                .transition(.opacity)
            } else if let welcomeLine {
                Label(welcomeLine, systemImage: "hand.wave.fill")
                    .foregroundStyle(.primary)
                    .fontWeight(.medium)
                    .minimumScaleFactor(0.8)
                    .transition(.opacity)
            } else if let finishedLine, viewModel.unmarkedCount == 0 {
                Label(finishedLine, systemImage: "sparkles")
                    .foregroundStyle(.primary)
                    .fontWeight(.medium)
                    .minimumScaleFactor(0.8)
                    .transition(.opacity)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .animation(.smooth(duration: 0.3), value: undo?.id)
        .animation(.smooth(duration: 0.3), value: finishedLine)
        .animation(.smooth(duration: 0.3), value: welcomeLine)
    }

    /// The class filling up along the bar's top edge: green for here, purple
    /// for left early, gray for absent, nothing yet for the rest.
    @ViewBuilder
    private var fillLine: some View {
        let rows = viewModel.rows
        if viewModel.dayOff == nil, !rows.isEmpty {
            let here = rows.count(where: \.isInRoom)
            let gone = rows.count { $0.status == .leftEarly }
            let away = rows.count { $0.status == .absent }
            GeometryReader { proxy in
                let unit = proxy.size.width / CGFloat(rows.count)
                HStack(spacing: 0) {
                    Rectangle().fill(Color.green).frame(width: unit * CGFloat(here))
                    Rectangle().fill(Color.purple).frame(width: unit * CGFloat(gone))
                    Rectangle().fill(Color(.tertiaryLabel)).frame(width: unit * CGFloat(away))
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 3)
            .animation(.smooth(duration: 0.35), value: here)
            .animation(.smooth(duration: 0.35), value: gone)
            .animation(.smooth(duration: 0.35), value: away)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Close Arrival while anyone's unmarked; "Late" once closed. Nothing
    /// ahead of the day (there's no arrival yet) or on a locked day, and no
    /// Close Arrival while the email button below offers it
    /// (`AssistantFrontDesk.offersCloseAndEmail`).
    private var showsArrivalControl: Bool { viewModel.showsArrivalControl }

    /// The email button below closes arrival now, so the plain one steps aside.
    private var emailClosesArrival: Bool {
        _ = dueTicks
        return viewModel.frontDesk.offersCloseAndEmail(by: viewModel)
    }

    @ViewBuilder
    private var arrivalControl: some View {
        if showsArrivalControl {
            switch viewModel.phase {
            case .arrival:
                if !unmarkedNames.isEmpty {
                    Button("Close Arrival") { confirmingClose = true }
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
                        .background(Color.lateAmber.opacity(0.16), in: Capsule())
                        .foregroundStyle(Color.lateAmber)
                }
                .accessibilityLabel("Arrival closed: a tap marks late")
                .accessibilityHint("Opens Reopen Arrival")
            }
        }
    }

    // MARK: - Closing

    private var unmarkedNames: [String] { viewModel.unmarkedNames }

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
