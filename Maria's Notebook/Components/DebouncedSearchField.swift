// DebouncedSearchField.swift
// Reusable debounced search field for pickers and lists.
// Adopt in LessonPickerComponents.swift to avoid heavy recomputation on every keystroke.

import SwiftUI

@MainActor
public struct DebouncedSearchField: View {
    private let title: String
    @Binding private var text: String
    private let debounceInterval: Duration
    private let onDebouncedChange: (String) -> Void

    @FocusState private var isFocused: Bool
    @State private var task: Task<Void, Never>?

    public init(
        _ title: String,
        text: Binding<String>,
        debounceInterval: Duration = .milliseconds(250),
        onDebouncedChange: @escaping (String) -> Void
    ) {
        self.title = title
        self._text = text
        self.debounceInterval = debounceInterval
        self.onDebouncedChange = onDebouncedChange
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(title, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit { triggerNow() }
            if !text.trimmed().isEmpty {
                Button {
                    text = ""
                    triggerNow()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        )
        .onChange(of: text) { _, newValue in
            scheduleDebounce(with: newValue)
        }
        .onAppear {
            // Kick off initial value
            scheduleDebounce(with: text)
        }
        .accessibilityElement(children: .combine)
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            isFocused = true
        }
        #endif
    }

    private func scheduleDebounce(with value: String) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: debounceInterval)
            onDebouncedChange(value)
        }
    }

    private func triggerNow() {
        task?.cancel()
        onDebouncedChange(text)
    }
}

#Preview {
    struct Demo: View {
        @State private var query: String = ""
        @State private var lastDebounced: String = ""
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                DebouncedSearchField("Search lessons", text: $query) { debounced in
                    lastDebounced = debounced
                }
                Text("Typed: \(query)")
                Text("Debounced: \(lastDebounced)")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 420)
        }
    }
    return Demo()
}
