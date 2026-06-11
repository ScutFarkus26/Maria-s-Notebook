// AppTips.swift
// TipKit tips for contextual feature discovery

import SwiftUI
import TipKit

/// Tip shown near the floating quick-note button
struct QuickNoteTip: Tip {
    var id: String { "quick-note-tip" }

    var title: Text {
        Text("Quick Actions")
    }

    var message: Text? {
        Text("Long-press this button for quick access to notes, presentations, work items, and to-dos.")
    }

    var image: Image? {
        Image(systemName: "sparkles")
    }
}

/// Tip shown on the Today view to encourage pull-to-refresh
struct PullToRefreshTip: Tip {
    var id: String { "pull-to-refresh-tip" }

    var title: Text {
        Text("Pull to Refresh")
    }

    var message: Text? {
        Text("Pull down on any list to refresh your data and sync with iCloud.")
    }

    var image: Image? {
        Image(systemName: "arrow.clockwise")
    }
}

/// Tip shown in the work detail view explaining the lifecycle
struct WorkLifecycleTip: Tip {
    var id: String { "work-lifecycle-tip" }

    var title: Text {
        Text("Work Lifecycle")
    }

    var message: Text? {
        Text(
            "Work items flow through stages: Active (in progress),"
            + " Review (checking work), and Complete (finished)."
            + " Tap the status to advance."
        )
    }

    var image: Image? {
        Image(systemName: "arrow.right.circle")
    }
}
