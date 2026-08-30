// WorksAgendaView+Chrome.swift
// The workspace's toolbar and iPhone header.
//
// Split from the view for SwiftLint's type-length limit; the state these read
// is declared in WorksAgendaView.swift.

import SwiftUI

extension WorksAgendaView {

    #if os(macOS)
    @ToolbarContentBuilder
    var lessonsAndWorkToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View", selection: workspaceKindBinding) {
                ForEach(WorkspaceKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(minWidth: 240, idealWidth: 300)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                appRouter.requestNewWork()
            } label: {
                Label("New Work", systemImage: "plus")
            }

            if showsWorkGrid {
                Picker("Sort", selection: $sortMode) {
                    ForEach(WorkAgendaSortMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                // Only under the All pill: the other pills already name a
                // state, and hiding scheduled work under Scheduled would empty
                // the list the pill promises.
                if workChip == .all {
                    Button {
                        hideScheduled.toggle()
                    } label: {
                        Label(
                            hideScheduled ? "Show Scheduled Work" : "Hide Scheduled Work",
                            systemImage: hideScheduled ? "calendar.badge.minus" : "calendar"
                        )
                    }
                    .help(hideScheduled ? "Show scheduled work" : "Hide scheduled work")
                }
            }

            if showsWorkGrid {
                Menu("Output", systemImage: "square.and.arrow.up") {
                    Button("Print", systemImage: "printer") {
                        printWorkView()
                    }
                    Button("Export PDF", systemImage: "arrow.down.doc") {
                        exportWorkPDF()
                    }
                }
            }
        }
    }
    #endif

    var mobileHeader: some View {
        VStack(spacing: 0) {
            ViewHeader(title: "Lessons & Work") {
                HStack(spacing: 12) {
                    Menu {
                        ForEach(WorkspaceKind.allCases) { kind in
                            Button {
                                workspaceKindBinding.wrappedValue = kind
                            } label: {
                                if kind == workspaceKind {
                                    Label(kind.title, systemImage: "checkmark")
                                } else {
                                    Label(kind.title, systemImage: kind.systemImage)
                                }
                            }
                        }
                    } label: {
                        Label(workspaceKind.title, systemImage: workspaceKind.systemImage)
                    }

                    Button {
                        appRouter.requestNewWork()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(searchPrompt, text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        searchDebounceTask?.cancel()
                        debouncedSearchText = searchText
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            if showsWorkGrid {
                WorkKindFilterChipBar(visibleKinds: visibleKinds)
                    .padding(.bottom, 4)
            }
        }
    }

    // MARK: - The pinned calendar pane
    //
    // The calendar sits under whichever list the guide is working from, so
    // scheduling something is a drag downward rather than a trip to another
    // screen. How tall it is lives in `WorksAgendaView+Split.swift`.

    var calendarPane: some View {
        VStack(spacing: 0) {
            calendarPaneHeader
            Divider()
            WeekPlanSection(
                focusedPresentationID: focusedPresentationID,
                onSelectPresentation: openPresentation,
                onOpenWork: openWork(id:)
            )
        }
    }

    /// Folded away, the calendar is only its header. The line above it belongs
    /// to the seam in `WorksAgendaView+Split.swift`; drawing one here as well
    /// is what used to double the rule whenever the calendar was collapsed.
    var collapsedCalendarBar: some View {
        calendarPaneHeader
    }

    var calendarPaneHeader: some View {
        Button {
            adaptiveWithAnimation(.snappy(duration: 0.2)) {
                isCalendarExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCalendarExpanded ? 90 : 0))
                Label("Scheduled", systemImage: TriageBucket.scheduled.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                Spacer()
                if !isCalendarExpanded {
                    Text("Show the week to drag onto it")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isCalendarExpanded ? "Hide the schedule" : "Show the schedule")
    }
}
