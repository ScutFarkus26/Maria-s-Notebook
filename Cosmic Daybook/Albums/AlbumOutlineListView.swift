// AlbumOutlineListView.swift
// Outline list

import SwiftUI

struct AlbumOutlineListView: View {
    @Environment(\.openWindow) private var openWindow
    let album: Album
    let currentPage: Int
    let onSelect: (AlbumOutlineNode) -> Void

    @State private var filter = ""
    @State private var selection: String?

    private var nodesByID: [String: AlbumOutlineNode] {
        var out: [String: AlbumOutlineNode] = [:]
        func walk(_ nodes: [AlbumOutlineNode]) {
            for node in nodes {
                out[node.id] = node
                if let children = node.children { walk(children) }
            }
        }
        walk(album.outline)
        return out
    }

    var body: some View {
        // `lesson(forPage:)` scans the outline: once per pass, not once per row.
        let currentLesson = album.lesson(forPage: currentPage)
        VStack(spacing: 0) {
            TextField("Filter contents", text: $filter)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            Divider()
            List(selection: $selection) {
                if filter.trimmingCharacters(in: .whitespaces).isEmpty {
                    OutlineGroup(album.outline, children: \.children) { node in
                        row(for: node, currentLesson: currentLesson)
                    }
                } else {
                    ForEach(filteredNodes) { node in
                        row(for: node, currentLesson: currentLesson)
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selection) {
                if let selection, let node = nodesByID[selection] {
                    onSelect(node)
                }
            }
        }
    }

    private var filteredNodes: [AlbumOutlineNode] {
        let needle = filter.folded()
        var out: [AlbumOutlineNode] = []
        func walk(_ nodes: [AlbumOutlineNode]) {
            for node in nodes {
                if node.title.folded().contains(needle) {
                    out.append(AlbumOutlineNode(id: node.id, title: node.title,
                                           pageIndex: node.pageIndex, children: nil))
                }
                if let children = node.children { walk(children) }
            }
        }
        walk(album.outline)
        return out
    }

    private func row(for node: AlbumOutlineNode, currentLesson: AlbumLessonRef?) -> some View {
        let isCurrent = currentLesson
            .map { $0.pageIndex == node.pageIndex && $0.title == node.title } ?? false
        return HStack {
            Text(node.title)
                .lineLimit(2)
                .fontWeight(isCurrent ? .semibold : .regular)
            Spacer(minLength: 6)
            Text("\(node.pageIndex + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .tag(node.id)
        .contextMenu {
            Button("Open in New Window") {
                openWindow(id: "AlbumWindow", value: "\(album.id)#\(node.pageIndex + 1)")
            }
        }
    }
}
