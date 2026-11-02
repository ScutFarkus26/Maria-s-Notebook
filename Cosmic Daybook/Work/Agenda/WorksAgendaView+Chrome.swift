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

        // The half's live list or its History, beside the half it belongs to.
        // Reports has no History.
        ToolbarItem(placement: .principal) {
            if workspaceKind != .reports {
                workspaceListPicker
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                newWorkInThisWindow()
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
                        newWorkInThisWindow()
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
            .clipRounded(UIConstants.CornerRadius.control)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            // The half's live list or its History. Reports has no History.
            if workspaceKind != .reports {
                workspaceListPicker
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
            if showsWorkGrid {
                WorkKindFilterChipBar(visibleKinds: visibleKinds)
                    .padding(.bottom, 4)
            }
        }
    }

    /// New Work opens in this window only: the router's request was obeyed by
    /// every open window (bug hunt 2026-10-11 #5). A window outside RootView
    /// has no per-window actions and falls back to the request.
    func newWorkInThisWindow() {
        if let quickCapture {
            quickCapture.newWork()
        } else {
            appRouter.requestNewWork()
        }
    }
}
