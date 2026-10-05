import SwiftUI
import CoreData

/// The office run: big check rows for what to grab from the office, and a
/// read-only list of what the guide is ordering, so nobody asks twice.
/// Checking off a shelf item marks it Stocked again, for everyone; a second
/// tap on a ticked row takes it back.
struct AssistantOfficeRunView: View {
    let model: AssistantRestockModel

    var body: some View {
        // Read so a check-off (the same objects, changed) redraws the rows.
        _ = model.revision
        return List {
            Section {
                if model.officeRun.isEmpty {
                    Text("Nothing to grab from the office.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.officeRun, id: \.objectID) { need in
                        runRow(need)
                    }
                }
            } header: {
                Text(subLine)
                    .font(.subheadline)
                    // The header is already dimmed: a plain `.secondary`
                    // here would dim it again, to a very light gray.
                    .foregroundStyle(Color(.secondaryLabel))
                    .textCase(nil)
            } footer: {
                if !model.officeRun.isEmpty {
                    Text("Checked-off shelf items go back to Stocked for everyone.")
                }
            }
            if !model.ordering.isEmpty {
                Section(model.orderingTitle) {
                    ForEach(model.ordering, id: \.objectID) { need in
                        orderRow(need)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Office run")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { model.load() }
    }

    /// "2 to grab", or thanks once it's all done.
    private var subLine: String {
        let left = model.officeRun.count { !model.isCheckedOff($0) }
        if model.officeRun.isEmpty { return "Nothing needed right now" }
        return left > 0 ? "\(left) to grab" : "All done. Thank you!"
    }

    private func runRow(_ need: CDOrderItem) -> some View {
        // Read in the row, which the list builds on its own: a check-off
        // changes the same object, so nothing else tells the row to redraw.
        _ = model.revision
        let done = model.isCheckedOff(need)
        let tag = AssistantRestockStyle.tag(for: model.staple(for: need))
        let detail = model.runDetail(need)
        let toggle = { withAnimation(.smooth(duration: 0.2)) { model.toggleCheckOff(need) } }
        return Button(action: toggle) {
            HStack(spacing: 14) {
                checkCircle(done: done)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(need))
                        .font(.body.weight(.semibold))
                        .strikethrough(done)
                        .foregroundStyle(done ? .secondary : .primary)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if !done, let tag {
                    tagPill(tag)
                }
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Holding a row says who asked for it; a tap is the same as "Got it".
        .contextMenu {
            Section {
                Button(
                    done ? "Put it back" : "Got it",
                    systemImage: done ? "arrow.uturn.backward" : "checkmark",
                    action: toggle
                )
            } header: {
                Text(model.runWho(need))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenTitle(need, done: done, tag: tag))
        .accessibilityValue(detail)
        .accessibilityHint(done ? "Double tap to put it back on the run" : "Double tap when you have it")
        .accessibilityAddTraits(.isButton)
    }

    /// The round check at the row's start: empty, or filled once ticked.
    private func checkCircle(done: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(done ? AssistantRestockStyle.accent : Color(.systemGray2), lineWidth: 2)
            if done {
                Circle().fill(AssistantRestockStyle.accent)
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AssistantRestockStyle.onAccent)
            }
        }
        .frame(width: 30, height: 30)
    }

    /// The small Out / Low tag at the row's end.
    private func tagPill(_ tag: AssistantRestockStyle.Tag) -> some View {
        Text(tag.text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(tag.foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tag.fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// "Toilet Paper, Out", "Toilet Paper, got it": the tag is left out when
    /// the row has none (a one-off, or a Stocked staple's need).
    private func spokenTitle(_ need: CDOrderItem, done: Bool, tag: AssistantRestockStyle.Tag?) -> String {
        if done { return "\(title(need)), got it" }
        guard let tag else { return title(need) }
        return "\(title(need)), \(tag.text)"
    }

    /// One of the guide's orders: what, how many, where it stands, and its link.
    private func orderRow(_ need: CDOrderItem) -> some View {
        _ = model.revision
        let content = HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(need))
                    .font(.body)
                    .foregroundStyle(.primary)
                if let host = need.host {
                    Label(host, systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(AssistantRestockStyle.accent)
                }
            }
            Spacer(minLength: 8)
            Text(model.orderStatus(need))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        return Group {
            if let url = need.url {
                Link(destination: url) { content }
                    .accessibilityHint("Opens the product page")
            } else {
                content
            }
        }
    }

    /// "Glue sticks ×12": the quantity when it's more than one.
    private func title(_ need: CDOrderItem) -> String {
        need.quantity > 1 ? "\(need.displayTitle) ×\(need.quantity)" : need.displayTitle
    }
}
