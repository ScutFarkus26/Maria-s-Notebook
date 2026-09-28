import SwiftUI

/// Compact app-wide classroom switcher used in the main toolbar.
struct ClassroomWorkspacePicker: View {
    let workspaceStore: ClassroomWorkspaceStore

    var body: some View {
        Menu {
            ForEach(ClassroomWorkspace.allCases) { workspace in
                Button {
                    Task { await workspaceStore.select(workspace) }
                } label: {
                    if workspaceStore.selection == workspace {
                        Label(workspace.displayName, systemImage: "checkmark")
                    } else {
                        Label(workspace.displayName, systemImage: workspace.systemImage)
                    }
                }
            }
        } label: {
            Label(
                workspaceStore.selection.displayName,
                systemImage: workspaceStore.selection.systemImage
            )
        }
        .disabled(workspaceStore.isPreparingSample)
        .help("Switch between My Class and the isolated Sample Class")
        .accessibilityLabel("Classroom")
        .accessibilityValue(workspaceStore.selection.displayName)
    }
}

#if os(iOS)
/// One compact context menu for iPhone. Combining classroom and school-year
/// selection prevents the app-level controls from colliding with each screen's
/// own navigation bar content.
struct MobileClassroomAndYearPicker: View {
    @Environment(\.dependencies) private var dependencies
    let workspaceStore: ClassroomWorkspaceStore
    var showsContextLabel = false

    private var yearStore: SchoolYearStore { dependencies.schoolYearStore }

    var body: some View {
        Menu {
            Section("Classroom") {
                ForEach(ClassroomWorkspace.allCases) { workspace in
                    Button {
                        Task { await workspaceStore.select(workspace) }
                    } label: {
                        selectionLabel(
                            workspace.displayName,
                            selected: workspaceStore.selection == workspace,
                            fallbackImage: workspace.systemImage
                        )
                    }
                }
            }

            Menu("School Year", systemImage: "calendar") {
                Button { yearStore.selectCurrentYear() } label: {
                    selectionLabel(
                        "This year (\(yearStore.current.label))",
                        selected: yearStore.isCurrentYearSelected
                    )
                }
                Button { yearStore.selectCurrentCycle() } label: {
                    selectionLabel(
                        "This cycle (\(yearStore.cycleYears) years)",
                        selected: yearStore.isCycleSelected
                    )
                }

                Divider()

                ForEach(yearStore.availableYears) { year in
                    Button { yearStore.select(year) } label: {
                        selectionLabel(year.label, selected: yearStore.isSelected(year))
                    }
                }

                Divider()

                Button { yearStore.selectAllTime() } label: {
                    selectionLabel("All years", selected: yearStore.isAllTimeSelected)
                }
            }
        } label: {
            if showsContextLabel {
                // Widest first; at large text sizes the calendar icon goes,
                // then the classroom name (its icon stays), so the bar never
                // wraps.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Image(systemName: workspaceStore.selection.systemImage)
                        Text(workspaceStore.selection.displayName)
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Image(systemName: "calendar")
                        Text(yearStore.menuButtonLabel)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: workspaceStore.selection.systemImage)
                        Text(workspaceStore.selection.displayName)
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(yearStore.menuButtonLabel)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: workspaceStore.selection.systemImage)
                        Text(yearStore.menuButtonLabel)
                    }
                }
                .lineLimit(1)
                .font(.subheadline.weight(.medium))
            } else {
                Image(systemName: workspaceStore.selection.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
        }
        .disabled(workspaceStore.isPreparingSample)
        .accessibilityLabel("Classroom and school year")
        .accessibilityValue(
            "\(workspaceStore.selection.displayName), \(yearStore.menuButtonLabel)"
        )
    }

    @ViewBuilder
    private func selectionLabel(
        _ title: String,
        selected: Bool,
        fallbackImage: String? = nil
    ) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else if let fallbackImage {
            Label(title, systemImage: fallbackImage)
        } else {
            Text(title)
        }
    }
}
#endif

/// Persistent reassurance while Sample Class is active. The banner is more
/// prominent than a toolbar title so a guide cannot mistake practice records
/// for the real classroom during a busy work cycle.
struct SampleClassroomBanner: View {
    let workspaceStore: ClassroomWorkspaceStore

    var body: some View {
        HStack(spacing: 12) {
            Label("Sample Class", systemImage: "testtube.2")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize()

            // The explanation is the first thing to give way in a narrow
            // window; the name and the way back always stay on one line.
            ViewThatFits(in: .horizontal) {
                Text("Practice data is local and completely separate from My Class.")
                Text("Separate from My Class.")
                Color.clear.frame(width: 0, height: 0)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Spacer(minLength: 0)

            Button("Return to My Class") {
                Task { await workspaceStore.select(.myClass) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.blue.opacity(0.10))
        .accessibilityElement(children: .contain)
    }
}
