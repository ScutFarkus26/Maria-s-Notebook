import SwiftUI

/// "Clean Up Leftovers": what would go, then the run. Nothing changes until the guide
/// presses Back Up and Clean Up; the backup is made and checked before any record is touched.
struct NotebookCleanupSheet: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(RestoreCoordinator.self) private var restoreCoordinator: RestoreCoordinator?
    @State private var model: NotebookCleanupModel?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Clean Up Leftovers")
                .font(.title2.weight(.semibold))
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .padding(AppTheme.Spacing.large)
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 440)
        #endif
        .interactiveDismissDisabled(model?.isWorking == true)
        .task {
            let restore = restoreCoordinator
            let made = NotebookCleanupModel(dependencies: dependencies) { restore?.isRestoring ?? false }
            model = made
            await made.load()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model?.stage ?? .loading {
        case .loading:
            ProgressView("Looking for leftovers…")
        case .ready(let counts):
            ready(counts, blocker: model?.blocker)
        case .backingUp:
            ProgressView("Making a backup and checking it…")
        case .cleaning:
            ProgressView("Cleaning up…")
        case .finished(let counts):
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Label("Done.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.success)
                countList(counts)
                Text("Your iPhone and iPad pick up the changes from iCloud.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColors.warning)
        }
    }

    @ViewBuilder
    private func ready(_ counts: NotebookJunkCleanup.Counts, blocker: String?) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            if counts.isEmpty {
                Text("Nothing to clean up.")
            } else {
                Text("These are bits left over from older versions of the app, and entries with nothing in them. "
                    + "Nothing you can see in your notebook changes.")
                    .font(.callout)
                VStack(alignment: .leading, spacing: 4) {
                    Text("What changes").font(.headline)
                    countList(counts)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Before you start").font(.headline)
                    Text("• A backup is made and checked first.")
                    Text("• Planned lessons for children who've left are marked skipped, not deleted.")
                    Text("• Your iPhone and iPad pick up the changes from iCloud.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            if let blocker {
                Label(blocker, systemImage: "hand.raised.fill")
                    .foregroundStyle(AppColors.warning)
            }
        }
    }

    private func countList(_ counts: NotebookJunkCleanup.Counts) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(counts.lines, id: \.self) { line in
                Text("• \(line)").font(.callout)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            switch model?.stage ?? .loading {
            case .ready(let counts):
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if !counts.isEmpty {
                    Button("Back Up and Clean Up") {
                        Task { await model?.start() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model?.blocker != nil)
                }
            case .finished, .failed:
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            case .loading, .backingUp, .cleaning:
                EmptyView()
            }
        }
    }
}

/// Settings › Troubleshooting: the way into `NotebookCleanupSheet`. Mac only.
struct NotebookCleanupCard: View {
    @State private var showingCleanup = false

    var body: some View {
        SettingsGroup(
            .cleanUp,
            footer: "Removes bits left over from older versions of the app, blank entries and duplicates. "
                + "You see the list before anything changes."
        ) {
            Button {
                showingCleanup = true
            } label: {
                Label("Clean Up Leftovers…", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .sheet(isPresented: $showingCleanup) {
                NotebookCleanupSheet()
            }
        }
    }
}
