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
                VStack(alignment: .leading, spacing: 14) {
                    Text(subLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                    Text("Grab these")
                }
            } footer: {
                if !model.officeRun.isEmpty {
                    Text("Checking off a shelf item marks it Stocked again, for everyone.")
                }
            }
            if !model.ordering.isEmpty {
                Section("Your guide is ordering") {
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

    /// "2 to grab · check off as you go", or thanks once it's all done.
    private var subLine: String {
        let left = model.officeRun.count { !model.isCheckedOff($0) }
        if model.officeRun.isEmpty { return "Nothing needed right now" }
        return left > 0 ? "\(left) to grab · check off as you go" : "All done. Thank you!"
    }

    private func runRow(_ need: CDOrderItem) -> some View {
        // Read in the row, which the list builds on its own: a check-off
        // changes the same object, so nothing else tells the row to redraw.
        _ = model.revision
        let done = model.isCheckedOff(need)
        let tag = AssistantRestockStyle.tag(for: model.staple(for: need)?.level)
        return Button {
            withAnimation(.smooth(duration: 0.2)) { model.toggleCheckOff(need) }
        } label: {
            HStack(spacing: 14) {
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(need))
                        .font(.body.weight(.semibold))
                        .strikethrough(done)
                        .foregroundStyle(done ? .secondary : .primary)
                    Text(model.runDetail(need))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if !done {
                    Text(tag.text)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tag.foreground)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(tag.fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title(need)), \(done ? "got it" : tag.text)")
        .accessibilityValue(model.runDetail(need))
        .accessibilityHint(done ? "Double tap to put it back on the run" : "Double tap when you have it")
        .accessibilityAddTraits(.isButton)
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
