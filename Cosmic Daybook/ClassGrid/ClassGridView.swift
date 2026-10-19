// ClassGridView.swift
// The Class Grid (Simplify the app, Phase 5; canvas approved 2026-10-18): one
// screen with four views of the class against the curriculum.
//
//   Checklist    the Checklist's grid and every tool it had
//   Three Years  the class Three-Year View: children by year in class
//   Children     the Progress Dashboard: one row per child, a strip per sequence
//   Recall       Lesson Recall: retention, by child, the due queue, the check
//
// The view switch is a segmented control in the Mac toolbar and tabs under the
// title on iPad and iPhone. The area menu, the search and the children filter
// belong to the screen, so they carry across views (`ClassGridScope`); the
// search carries only between fields that look through the same thing, and a
// view with no field ignores it. Each view adds its own tools (the Checklist's
// lens, Three Years' sequence menu and Key / All).
//
// It opens at the Checklist's destination. Until Phase 11 aliases them, the
// Three-Year View, Progress Dashboard and Lesson Recall destinations open it on
// their view (ClassGridDestinations.swift).

import CoreData
import SwiftUI

struct ClassGridView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appRouter) private var appRouter
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var selection: ClassGridViewKind
    @State private var scope = ClassGridScope()
    @TestStudentVisibility private var testStudents

    /// The view the grid opens on; set once, here, rather than on appear.
    let initialView: ClassGridViewKind

    init(initialView: ClassGridViewKind = .checklist) {
        self.initialView = initialView
        _selection = State(initialValue: initialView)
    }

    /// The Mac and a regular-width iPad put the screen's controls in the toolbar;
    /// an iPhone keeps a row of them under the title.
    private var usesRegularLayout: Bool {
        #if os(macOS)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    var body: some View {
        page
            .environment(scope)
            .onAppear(perform: loadScope)
            .onChange(of: testStudents.show) { _, _ in loadScope() }
            .onChange(of: testStudents.namesRaw) { _, _ in loadScope() }
            .onChange(of: selection, initial: true) { _, view in
                scope.viewDidChange(to: view, isRegular: usesRegularLayout)
            }
            // "Show in Checklist" and "View Class Progress" name a Checklist row or
            // band: whichever view is showing, the grid turns to the Checklist,
            // which takes the request as it loads.
            .onChange(of: appRouter.checklistLessonRequest) { _, request in
                if request != nil { selection = .checklist }
            }
            .onChange(of: appRouter.checklistFilterArea) { _, area in
                if area != nil { selection = .checklist }
            }
            // A retired row (Three-Year View, Progress Dashboard, Lesson
            // Recall) opens the grid on its view.
            .onChange(of: appRouter.screenLanding, initial: true) { _, _ in
                if let view = appRouter.consumeScreenLanding(where: { landing -> ClassGridViewKind? in
                    if case .classGrid(let view) = landing { return view }
                    return nil
                }) {
                    selection = view
                }
            }
    }

    private func loadScope() {
        scope.load(context: viewContext, showTestStudents: testStudents.show, testNamesRaw: testStudents.namesRaw)
    }

    // MARK: - Pages

    @ViewBuilder
    private var page: some View {
        #if os(macOS)
        macPage
        #else
        if usesRegularLayout {
            // The iPad gives a sidebar page no navigation bar, so the page brings
            // its own stack (none when pushed into the iPad mini's More stack).
            PageNavigationStack { regularPage }
        } else {
            compactPage
        }
        #endif
    }

    #if os(macOS)
    /// The Mac: the area menu by the title, the view switch in the middle of the
    /// toolbar, the search field and the children filter at its end.
    private var macPage: some View {
        content
            .navigationTitle("Class Grid")
            .toolbar {
                ToolbarItem(placement: .navigation) { areaMenu }
                ToolbarItem(placement: .principal) {
                    viewSwitch
                        .pickerStyle(.segmented)
                        .fixedSize()
                }
                ToolbarItem(placement: .primaryAction) { childrenFilter }
            }
            .modifier(ClassGridSearch(view: selection, scope: scope))
    }
    #else
    /// The iPad: the title, the area menu and the children filter in the
    /// navigation bar, and the views as tabs under it.
    private var regularPage: some View {
        VStack(spacing: 0) {
            viewSwitch
                .pickerStyle(.tabs)
                .padding(.horizontal, 16)
            Divider()
            content
        }
        .navigationTitle("Class Grid")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { areaMenu }
            ToolbarItem(placement: .primaryAction) { childrenFilter }
        }
        .modifier(ClassGridSearch(view: selection, scope: scope))
    }

    /// The iPhone, under More: the area menu with the view's search field (or
    /// its caption), the views as tabs, then the view.
    private var compactPage: some View {
        VStack(spacing: 0) {
            ClassGridCompactScopeRow(view: selection, areaMenu: { areaMenu })
            viewSwitch
                .pickerStyle(.tabs)
                .padding(.horizontal, 4)
            Divider()
            content
        }
        .navigationTitle("Class Grid")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) { childrenFilter }
        }
    }
    #endif

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .checklist: ClassGridChecklistView()
        case .threeYears: ClassGridYearsView()
        case .children: ClassGridChildrenView()
        case .recall: ClassGridRecallView()
        }
    }

    // MARK: - Controls

    private var viewSwitch: some View {
        Picker("View", selection: $selection) {
            ForEach(ClassGridViewKind.allCases) { view in
                Text(view.title).tag(view)
            }
        }
        .labelsHidden()
        .accessibilityLabel("View")
    }

    /// "Math ⌄": the area every view shows. The Checklist shows one area; the
    /// other views can show them all.
    private var areaMenu: some View {
        let view = selection
        return Menu {
            Picker("Area", selection: Binding(
                get: { scope.menuSelection(for: view) },
                set: { scope.pick(area: $0) }
            )) {
                if view.allowsAllAreas {
                    Text("All areas").tag(String?.none)
                }
                ForEach(scope.areas, id: \.self) { area in
                    Text(area).tag(String?.some(area))
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Text(scope.menuTitle(for: view))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose a curriculum area")
        .accessibilityLabel("Curriculum area: \(scope.menuTitle(for: view))")
    }

    private var childrenFilter: some View {
        ChecklistStudentFilterButton(
            studentFilterIDs: $scope.childFilterIDs,
            rosterStudents: scope.roster,
            isToolbarItem: true
        )
    }
}

// MARK: - Search

/// The toolbar search field on the Mac and iPad, bound to the grid's one search
/// text. Three Years has no search on the canvas, so the field goes there.
private struct ClassGridSearch: ViewModifier {
    let view: ClassGridViewKind
    @Bindable var scope: ClassGridScope

    func body(content: Content) -> some View {
        if view == .threeYears {
            content
        } else {
            content.searchable(text: $scope.searchText, prompt: Text(scope.searchPrompt(for: view)))
        }
    }
}

#if os(iOS)
/// The iPhone's row under the title: the area menu, then the view's search
/// field, or Three Years' caption. Recall searches nothing on the phone.
private struct ClassGridCompactScopeRow<AreaMenu: View>: View {
    let view: ClassGridViewKind
    @ViewBuilder let areaMenu: () -> AreaMenu
    @Environment(ClassGridScope.self) private var scope

    var body: some View {
        @Bindable var scope = scope
        HStack(spacing: 8) {
            areaMenu()
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            switch view {
            case .checklist, .children:
                DebouncedSearchField(
                    view == .checklist ? "Filter lessons" : "Search children",
                    text: $scope.searchText,
                    onDebouncedChange: { _ in }
                )
                .padding(.horizontal, 9)
                .frame(height: 32)
                .background(Color.primary.opacity(UIConstants.OpacityConstants.faint), in: .rect(cornerRadius: 10))
            case .threeYears:
                Text("Furthest mark · oldest first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            case .recall:
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }
}
#endif
