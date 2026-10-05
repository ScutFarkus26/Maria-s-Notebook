import SwiftUI
import CoreData

/// "We need…": something that isn't on the shelf, asked for once. A name,
/// where it comes from (the office, or ordered by the guide) and how many.
/// Naming a staple marks it Out instead. Pasting a link suggests a product
/// and switches to Needs ordering. Only the guide sends the order email, so
/// there's no Draft Request here.
struct AssistantWeNeedSheet: View {
    let model: AssistantRestockModel

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var source = RestockSource.office
    @State private var quantity = 1
    @State private var notice: String?
    @FocusState private var nameFocused: Bool

    private var trimmed: String { name.trimmed() }
    private var staple: CDSupply? { model.staple(named: trimmed) }
    private var isLink: Bool { AssistantRestockModel.pastedLink(trimmed) != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("What do we need?", text: $name)
                        .font(.title3)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .onSubmit(add)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 50)
                        .background(Color(.secondarySystemGroupedBackground), in: fieldShape)
                        .overlay { fieldShape.strokeBorder(AssistantRestockStyle.accent, lineWidth: 2) }
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    if staple == nil {
                        sourcePicker
                        quantityRow
                    }
                    Button(action: add) {
                        Text(goLabel)
                            .font(.headline)
                            .foregroundStyle(AssistantRestockStyle.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(AssistantRestockStyle.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmed.isEmpty)
                    .opacity(trimmed.isEmpty ? 0.5 : 1)
                    if let notice {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    siriTip
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("We need…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { nameFocused = true }
        .onChange(of: isLink) { _, link in
            // A pasted product link is something to order.
            if link { source = .order }
        }
        .onChange(of: name) { notice = nil }
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    private var hint: String {
        if let staple {
            return "\(staple.name) is on the shelf. This marks it Out."
        }
        return "Not on the shelf, so this asks once. Paste a link to suggest a product."
    }

    private var goLabel: String {
        if staple != nil { return "Mark It Out" }
        return source == .office ? "Add to Office Run" : model.askToOrder
    }

    private var sourcePicker: some View {
        HStack(spacing: 10) {
            sourceOption(.office, title: "From the office", detail: "On the next office run", icon: "building.2")
            sourceOption(.order, title: "Needs ordering", detail: model.sendsTheOrder, icon: "cart")
        }
    }

    private func sourceOption(_ option: RestockSource, title: String, detail: String, icon: String) -> some View {
        let chosen = source == option
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            source = option
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(AssistantRestockStyle.accent)
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .padding(12)
            .background(chosen ? AssistantRestockStyle.accentSoft : Color(.secondarySystemGroupedBackground), in: shape)
            .overlay {
                shape.strokeBorder(chosen ? AssistantRestockStyle.accent : Color(.separator), lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private var quantityRow: some View {
        HStack {
            Text("How many")
            Spacer()
            Button {
                quantity = max(OrderService.quantityRange.lowerBound, quantity - 1)
            } label: {
                Image(systemName: "minus").frame(width: 44, height: 36)
            }
            .accessibilityLabel("Fewer")
            .disabled(quantity <= OrderService.quantityRange.lowerBound)
            Text("\(quantity)")
                .font(.headline)
                .monospacedDigit()
                .frame(minWidth: 40)
            Button {
                quantity = min(OrderService.quantityRange.upperBound, quantity + 1)
            } label: {
                Image(systemName: "plus").frame(width: 44, height: 36)
            }
            .accessibilityLabel("More")
        }
        .buttonStyle(.bordered)
        .tint(AssistantRestockStyle.accent)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(minHeight: 52)
        .background(Color(.secondarySystemGroupedBackground), in: fieldShape)
        .accessibilityElement(children: .contain)
    }

    private var siriTip: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic")
                .foregroundStyle(AssistantRestockStyle.accent)
            Text("Or say “We're out of paper towels in Daybook Assistant.”")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: fieldShape)
    }

    private func add() {
        switch model.addNeed(trimmed, source: source, quantity: quantity) {
        case .added, .markedStaple:
            dismiss()
        case .alreadyListed:
            notice = "That's already on the list."
        case .nothing:
            break
        }
    }
}
