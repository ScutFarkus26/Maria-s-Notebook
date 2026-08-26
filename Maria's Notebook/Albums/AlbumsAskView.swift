// AlbumsAskView.swift
// "Ask the Albums": a conversation with the on-device model, grounded in
// excerpts retrieved from the albums for each question. Answers cite
// numbered sources the user can jump to. The whole exchange stays on
// device; when Apple Intelligence is unavailable the view explains why.

import SwiftUI

struct AlbumsAskView: View {
    @Environment(AlbumLibrary.self) private var library
    @Environment(AlbumsNavModel.self) private var nav
    @Environment(AlbumIntelligence.self) private var intelligence

    @State private var question = ""
    @State private var history: [AlbumAskExchange] = []
    @FocusState private var inputFocused: Bool

    private let suggestions = [
        "Where do I introduce the checkerboard?",
        "How do I present the parts of a flower?",
        "Which lessons lead up to long division?",
        "What materials do I need for the First Great Lesson?"
    ]

    var body: some View {
        VStack(spacing: 0) {
            if let explanation = intelligence.unavailableExplanation {
                ContentUnavailableView {
                    Label("Apple Intelligence Unavailable", systemImage: "sparkles.slash")
                } description: {
                    Text(explanation)
                }
            } else if history.isEmpty {
                emptyState
            } else {
                conversation
            }
            Divider()
            inputBar
        }
        .navigationTitle("Ask the Albums")
        .toolbar {
            ToolbarItem {
                Button {
                    history = []
                    intelligence.resetConversation()
                } label: {
                    Label("New Conversation", systemImage: "plus.bubble")
                }
                .disabled(history.isEmpty)
                .help("Start a fresh conversation")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Ask in plain language")
                .font(.title2.bold())
            Text("Answers come from your own album text, generated entirely on this device, "
                 + "with page references you can jump to.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        ask(suggestion)
                    } label: {
                        Text(suggestion)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.quaternary.opacity(0.5), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!library.indexReady)
                }
            }
            if !library.indexReady {
                Text("One moment — still indexing the albums…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .frame(maxHeight: .infinity)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(history) { exchange in
                        ExchangeView(exchange: exchange)
                            .id(exchange.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: history.last?.answer) {
                if let last = history.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask anything about your albums…", text: $question)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .onSubmit { ask(question) }
            Button {
                ask(question)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || !canAsk)
        }
        .padding(12)
        .background(.bar)
    }

    private var canAsk: Bool {
        intelligence.isAvailable && library.indexReady && !(history.last?.isRunning ?? false)
    }

    private func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canAsk else { return }
        question = ""
        let exchange = AlbumAskExchange(question: trimmed)
        history.append(exchange)
        let corpus = library.corpus()
        let id = exchange.id
        Task {
            do {
                var boost: [String: [Float]]?
                if let queryVector = await library.semantic.queryVector(for: trimmed) {
                    var scores: [String: [Float]] = [:]
                    for album in corpus.albums {
                        scores[album.id] = library.semantic.normalizedSimilarities(query: queryVector,
                                                                                   albumID: album.id)
                    }
                    boost = scores
                }
                let answer = try await intelligence.answer(question: trimmed, corpus: corpus,
                                                           semanticBoost: boost)
                update(id: id) { $0.answer = answer.text; $0.sources = answer.sources }
            } catch {
                update(id: id) { $0.error = error.localizedDescription }
            }
        }
    }

    private func update(id: UUID, _ mutate: (inout AlbumAskExchange) -> Void) {
        guard let i = history.firstIndex(where: { $0.id == id }) else { return }
        mutate(&history[i])
    }
}

private struct ExchangeView: View {
    @Environment(AlbumsNavModel.self) private var nav
    let exchange: AlbumAskExchange

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer(minLength: 60)
                Text(exchange.question)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
            }
            if exchange.isRunning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the albums…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if let error = exchange.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            } else if let answer = exchange.answer {
                VStack(alignment: .leading, spacing: 10) {
                    Text(markdown(answer))
                        .textSelection(.enabled)
                    if !exchange.sources.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Sources")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            ForEach(exchange.sources) { source in
                                Button {
                                    nav.jump(albumID: source.albumID,
                                                  pageIndex: source.pageIndex)
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("[\(source.id)]")
                                            .font(.caption.monospacedDigit().bold())
                                        Text("\(source.albumTitle) · \(source.lessonTitle) "
                                             + "· p. \(source.pageIndex + 1)")
                                            .font(.caption)
                                            .underline()
                                    }
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.tint)
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}
