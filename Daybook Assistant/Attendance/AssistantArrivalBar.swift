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
/// When the guide picked ParentLocker, today's Close Arrival is **Close
/// Arrival & Send**: the class goes to ParentLocker once the Undo's moment
/// has passed (`ParentLockerSync.closeArrivalUndoWindow`), and the Undo
/// stops the send as well, since ParentLocker can't take a mark back. The
/// Undo goes when the send does. On an iPhone not signed in, arrival still
/// closes and the Undo stays (nothing goes before she signs in); the
/// one-time sign-in opens once the Undo's moment has passed, so it never
/// covers the Undo (bug check 2026-10-13, D2), and signing in sends the class
/// and takes the Undo away.
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
    /// Close Arrival & Send on an iPhone not signed in to ParentLocker.
    @State private var showingSignIn = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AssistantBootstrapper.self) private var bootstrapper

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
        // Bar text stops growing at the first accessibility size: at the
        // largest one the bar took half an SE's screen and left the grid
        // half a row.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
        .overlay(alignment: .top) { fillLine }
        // Her own close, reopen or Undo only: an import moving the phase
        // (another device closing arrival) used to buzz too.
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.phaseSwitches)
        .onChange(of: viewModel.asksToCloseAndEmail, initial: true) { _, asks in
            // A tapped front-desk reminder with children still unmarked
            // (`AssistantFrontDeskMail`): the same question as Close
            // Arrival & Email, rather than an email that leaves them out.
            guard asks else { return }
            viewModel.asksToCloseAndEmail = false
            // With ParentLocker picked, the question is Close Arrival & Send's.
            emailAfterClose = !viewModel.frontDesk.sendsToParentLocker
            confirmingClose = true
        }
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
            Button(closeButtonTitle, role: .destructive) {
                closeArrival()
            }
        } message: {
            Text("\(unmarkedNames.formatted(.list(type: .and))). After this, a tap marks a child late.")
        }
        .onChange(of: confirmingClose) { _, showing in
            if !showing { emailAfterClose = false }
        }
        .task(id: undoWatch) { await watchUndo() }
        .sheet(isPresented: $showingSignIn) {
            if let sync = bootstrapper.parentLockerForScreens {
                ParentLockerSignInSheet(sync: sync)
            }
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
                        if undo.stopsSend { bootstrapper.parentLockerForScreens?.cancelCloseArrivalSend() }
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

    /// Close Arrival while anyone's unmarked, or after Reopen Arrival while
    /// Close Arrival's absences stand; "Late" once closed. Nothing ahead of
    /// the day (there's no arrival yet) or on a locked day, and no Close
    /// Arrival while the email button below offers it
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
                // With nobody left to mark (reopened while Close Arrival's
                // absences stand), it goes straight back to Late: there's
                // no one to ask about.
                Button(sendsOnClose ? "Close Arrival & Send" : "Close Arrival") {
                    if unmarkedNames.isEmpty { closeArrival() } else { confirmingClose = true }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .accessibilityHint(
                    unmarkedNames.isEmpty
                        ? "Back to Late: a tap marks a child late"
                        : "Asks before marking everyone not here yet absent"
                )
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

    /// Close Arrival sends the class to ParentLocker too.
    private var sendsOnClose: Bool {
        viewModel.frontDesk.closesWithSend(by: viewModel, hasSync: bootstrapper.parentLockerForScreens != nil)
    }

    /// The question's plain close: "Mark 3 Absent", or "Mark 3 Absent & Send".
    private var closeButtonTitle: String {
        Self.closeButtonTitle(unmarked: unmarkedNames.count, sends: sendsOnClose)
    }

    static func closeButtonTitle(unmarked: Int, sends: Bool) -> String {
        "Mark \(unmarked) Absent" + (sends ? " & Send" : "")
    }

    private func closeArrival() {
        let sync = sendsOnClose ? bootstrapper.parentLockerForScreens : nil
        withAnimation(.smooth(duration: 0.3)) {
            let count = viewModel.beginLate()
            undo = Self.undo(afterClosing: count, queuedSend: sync != nil, signedIn: sync?.isSignedIn == true)
        }
        // A locked day, say, stays open: nothing to send.
        guard let sync, viewModel.phase == .late else { return }
        // A second after the Undo goes, so a last-instant Undo still stops it.
        sync.closeArrivalSend(on: viewModel.date, after: ParentLockerSync.closeArrivalUndoWindow + 1)
        // Not signed in: the sheet waits for the Undo's moment (`watchUndo`),
        // unless there's no Undo to keep in reach.
        if !sync.isSignedIn, undo == nil { showingSignIn = true }
    }
}

// MARK: - Close Arrival & Send's Undo

extension AssistantArrivalBar {

    /// The Undo after closing arrival with `count` marked absent. With a
    /// ParentLocker send queued, Undo stops it (`stopsSend`); only a phone
    /// signed in sends when the Undo's moment passes, so only its Undo goes
    /// then (`sendsToParentLocker`). Nil when nobody was marked.
    static func undo(afterClosing count: Int, queuedSend: Bool, signedIn: Bool) -> ArrivalUndo? {
        guard count > 0 else { return nil }
        return ArrivalUndo(count: count, sendsToParentLocker: queuedSend && signedIn, stopsSend: queuedSend)
    }

    /// What happens once Close Arrival & Send's Undo moment has passed.
    enum AfterUndoWindow: Equatable {
        /// The class has gone to ParentLocker: Undo can't take it back.
        case hideUndo
        /// Nothing has gone (not signed in): the sign-in opens, and the Undo stays.
        case askToSignIn
    }

    static func afterUndoWindow(signedIn: Bool) -> AfterUndoWindow {
        signedIn ? .hideUndo : .askToSignIn
    }

    /// What `watchUndo` follows: the Undo on offer, and the sign-in.
    private var undoWatch: String {
        "\(undo?.id.uuidString ?? "")|\(bootstrapper.parentLockerForScreens?.isSignedIn == true)"
    }

    /// The moment Close Arrival & Send's Undo stops being offered: when the
    /// class goes.
    /// When this Undo stops being safe (bug check 2026-10-13, D2): the
    /// sync's "Undo ends at", when the send goes; without one, Close
    /// Arrival's own Undo window from the close.
    private func undoEnds(for undo: ArrivalUndo) -> Date {
        bootstrapper.parentLockerForScreens?.undoEndsAt
            ?? undo.closedAt.addingTimeInterval(ParentLockerSync.closeArrivalUndoWindow)
    }

    /// Waits out Close Arrival & Send's Undo, then hides it (signed in: the
    /// class has gone) or opens the sign-in (not: the Undo stays until she
    /// signs in, which runs this again and hides it).
    private func watchUndo() async {
        guard let undo, undo.stopsSend else { return }
        let wait = undoEnds(for: undo).timeIntervalSinceNow
        if wait > 0 { guard (try? await Task.sleep(for: .seconds(wait))) != nil else { return } }
        guard self.undo?.id == undo.id else { return }
        switch Self.afterUndoWindow(signedIn: bootstrapper.parentLockerForScreens?.isSignedIn == true) {
        case .hideUndo:
            withAnimation(.smooth(duration: 0.3)) { self.undo = nil }
        case .askToSignIn:
            showingSignIn = true
        }
    }
}

/// The Undo offered after closing arrival.
struct ArrivalUndo: Equatable {
    let id = UUID()
    let count: Int
    /// Close Arrival & Send on a phone signed in: the class goes once the
    /// Undo's moment passes, and the Undo goes with it.
    var sendsToParentLocker = false
    /// A ParentLocker send waits on this close: Undo stops it too. On a phone
    /// not signed in, the Undo stays past its moment and still stops it.
    var stopsSend = false
    /// When arrival closed: the Undo's moment counts from here.
    var closedAt = Date()
}
