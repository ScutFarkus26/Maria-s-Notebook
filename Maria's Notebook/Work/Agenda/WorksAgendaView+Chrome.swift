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
            Picker("View", selection: workspaceScopeBinding) {
                ForEach(TriageBucket.listCases) { bucket in
                    Text(bucket.title).tag(bucket)
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

            if workspaceScope == .attention {
                Toggle(isOn: $showAllOpenWork) {
                    Label("All Open Work", systemImage: "tray.full")
                }
                .toggleStyle(.button)
                .help("Show every open work item, not only what needs you")
            }

            if showsWorkGrid {
                Picker("Sort", selection: $sortMode) {
                    ForEach(WorkAgendaSortMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)

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
                        ForEach(TriageBucket.listCases) { bucket in
                            Button {
                                workspaceScopeBinding.wrappedValue = bucket
                            } label: {
                                if bucket == workspaceScope {
                                    Label(bucket.title, systemImage: "checkmark")
                                } else {
                                    Label(bucket.title, systemImage: bucket.systemImage)
                                }
                            }
                        }
                        if workspaceScope == .attention {
                            Divider()
                            Toggle("All Open Work", isOn: $showAllOpenWork)
                        }
                    } label: {
                        Label(workspaceScope.compactTitle, systemImage: workspaceScope.systemImage)
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

    var collapsedCalendarBar: some View {
        VStack(spacing: 0) {
            Divider()
            calendarPaneHeader
        }
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
