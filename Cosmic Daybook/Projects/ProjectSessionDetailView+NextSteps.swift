import SwiftUI

// MARK: - Questions and Next Steps

extension ProjectSessionDetailView {

    var agendaItemsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Student Questions & Next Steps")
                .font(.headline)
            ForEach(Array(session.agendaItems.enumerated()), id: \.offset) { index, _ in
                HStack {
                    TextField("Question, observation, or next step", text: Binding(
                        get: {
                            session.agendaItems.indices.contains(index)
                                ? session.agendaItems[index] : ""
                        },
                        set: { newValue in
                            var items = session.agendaItems
                            if items.indices.contains(index) {
                                items[index] = newValue
                                session.agendaItems = items
                            }
                        }
                    ), axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) {
                        var items = session.agendaItems
                        if items.indices.contains(index) {
                            items.remove(at: index)
                            session.agendaItems = items
                            saveProjectSession(reason: "Remove Project Next Step")
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(AppColors.destructive)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                var items = session.agendaItems
                items.append("")
                session.agendaItems = items
                saveProjectSession(reason: "Add Project Next Step")
            } label: {
                Label("Add Next Step", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain)
        }
    }
}
