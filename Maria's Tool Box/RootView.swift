import SwiftUI
import SwiftData

struct RootView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case students = "Students"
        case albumlessons = "Albums"         // Lessons library (albums view)
        case planning = "Planning"
        case studentLessons = "Lessons" // Student lessons (pills)
        case work = "Work"
        case settings = "Settings"
        case attendance = "Attendance"

        var id: String { rawValue }
    }

    @SceneStorage("RootView.selectedTab") private var selectedTabRaw: String = Tab.albumlessons.rawValue
    @Environment(\.modelContext) private var modelContext
    @AppStorage("Backfill.relationships.v1") private var didBackfillRelationships: Bool = false
    @AppStorage("Backfill.isPresentedFromGivenAt.v1") private var didBackfillIsPresented: Bool = false

    private var selectedTab: Tab {
        Tab(rawValue: selectedTabRaw) ?? .albumlessons
    }
    
    private var pillTabs: [Tab] { Tab.allCases.filter { $0 != .attendance } }

    var body: some View {
        VStack(spacing: 0) {
            if UserDefaults.standard.bool(forKey: MariasToolboxApp.ephemeralSessionFlagKey) {
                let reason = UserDefaults.standard.string(forKey: MariasToolboxApp.lastStoreErrorDescriptionKey) ?? "The persistent store could not be opened. Data will not persist this session."
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Warning: Data won't persist this session").font(.callout).fontWeight(.semibold)
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        NotificationCenter.default.post(name: Notification.Name("CreateBackupRequested"), object: nil)
                    } label: {
                        Label("Backup Now", systemImage: "externaldrive.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.primary.opacity(0.1)), alignment: .bottom)
            }

            // Top pill navigation
            HStack {
                Spacer()

                HStack(spacing: 12) {
                    ForEach(pillTabs) { tab in
                        Button {
                            if tab == .albumlessons {
                                // Disable animation when switching to the Albums view
                                withAnimation(nil) {
                                    selectedTabRaw = tab.rawValue
                                }
                            } else {
                                selectedTabRaw = tab.rawValue
                            }
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: AppTheme.FontSize.body, weight: .semibold))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .frame(minHeight: 30)
                                .background(pillBackground(for: tab))
                                .foregroundStyle(pillForeground(for: tab))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
            }
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Active view
            Group {
                switch selectedTab {
                case .studentLessons:
                    StudentLessonsRootView()
                case .albumlessons:
                    LessonsRootView()
                case .students:
                    StudentsRootView()
                case .planning:
                    PlanningRootView()
                case .work:
                    WorkView()
                case .attendance:
                    AttendanceView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            backfillRelationshipsIfNeeded()
            backfillIsPresentedIfNeeded()
            // Migrate legacy top-level Attendance tab to Students -> Attendance mode
            if Tab(rawValue: selectedTabRaw) == .attendance {
                selectedTabRaw = Tab.students.rawValue
                UserDefaults.standard.set("Attendance", forKey: "StudentsRootView.mode")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BackfillIsPresentedRequested"))) { _ in
            backfillIsPresentedIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenAttendanceRequested"))) { _ in
            selectedTabRaw = Tab.students.rawValue
            UserDefaults.standard.set("Attendance", forKey: "StudentsRootView.mode")
        }
    }

    // MARK: - Styling

    private func pillBackground(for tab: Tab) -> some ShapeStyle {
        if tab == selectedTab {
            return AnyShapeStyle(Color.accentColor)
        } else {
            return AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
        }
    }

    private func pillForeground(for tab: Tab) -> some ShapeStyle {
        if tab == selectedTab {
            return AnyShapeStyle(Color.white)
        } else {
            return AnyShapeStyle(Color.primary)
        }
    }

    private func backfillRelationshipsIfNeeded() {
        guard !didBackfillRelationships else { return }
        do {
            let sls = try modelContext.fetch(FetchDescriptor<StudentLesson>())
            let students = try modelContext.fetch(FetchDescriptor<Student>())
            let lessons = try modelContext.fetch(FetchDescriptor<Lesson>())
            let studentsByID = Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
            let lessonsByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })

            var changed = false
            for sl in sls {
                let targetLesson = lessonsByID[sl.lessonID]
                let targetStudents = sl.studentIDs.compactMap { studentsByID[$0] }
                if sl.lesson?.id != targetLesson?.id { sl.lesson = targetLesson; changed = true }
                let currentIDs = Set(sl.students.map { $0.id })
                let targetIDs = Set(targetStudents.map { $0.id })
                if currentIDs != targetIDs {
                    sl.students = targetStudents
                    changed = true
                }
                if changed {
                    sl.syncSnapshotsFromRelationships()
                }
            }
            if changed {
                try modelContext.save()
            }
            didBackfillRelationships = true
        } catch {
            // If backfill fails, skip and try again next launch
        }
    }

    private func backfillIsPresentedIfNeeded() {
        do {
            let sls = try modelContext.fetch(FetchDescriptor<StudentLesson>())
            var changed = false
            for sl in sls {
                if sl.givenAt != nil && sl.isPresented == false {
                    sl.isPresented = true
                    changed = true
                }
            }
            if changed {
                try modelContext.save()
            }
        } catch {
            // If backfill fails, skip and try again next launch
        }
    }
}

struct PlanningRootView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case agenda = "Agenda"
        case board = "Board"
        var id: String { rawValue }
    }

    @AppStorage("PlanningRootView.mode") private var modeRaw: String = Mode.agenda.rawValue
    private var mode: Mode { Mode(rawValue: modeRaw) ?? .agenda }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    PillNavButton(title: Mode.agenda.rawValue, isSelected: mode == .agenda) {
                        modeRaw = Mode.agenda.rawValue
                    }
                    PillNavButton(title: Mode.board.rawValue, isSelected: mode == .board) {
                        modeRaw = Mode.board.rawValue
                    }
                }
                Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, 8)

            Divider()

            Group {
                if mode == .agenda {
                    PlanningAgendaView()
                } else {
                    PlanningWeekView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

