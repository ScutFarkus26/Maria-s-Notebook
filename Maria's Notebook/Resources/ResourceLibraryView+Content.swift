// ResourceLibraryView+Content.swift
// Resource grid/list display and selectable card/row wrappers.

import SwiftUI

extension ResourceLibraryView {

    // MARK: - Resource Content (Grid or List)

    @ViewBuilder
    func resourceContent(_ resources: [Resource]) -> some View {
        switch viewMode {
        case .grid:
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(resources) { resource in
                    if isSelectMode {
                        selectableCard(resource: resource)
                    } else {
                        ResourceCard(resource: resource) {
                            selectedResource = resource
                        } onDelete: {
                            deleteResource(resource)
                        } onRename: {
                            renameText = resource.title
                            resourceToRename = resource
                        } onChangeCategory: {
                            resourceToRecategorize = resource
                        }
                    }
                }
            }
        case .list:
            VStack(spacing: 8) {
                ForEach(resources) { resource in
                    if isSelectMode {
                        selectableRow(resource: resource)
                    } else {
                        ResourceRow(resource: resource)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedResource = resource
                            }
                            .contextMenu {
                                Button {
                                    selectedResource = resource
                                } label: {
                                    Label("View Details", systemImage: "eye")
                                }

                                Button {
                                    renameText = resource.title
                                    resourceToRename = resource
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Button {
                                    resourceToRecategorize = resource
                                } label: {
                                    Label("Change Category", systemImage: "folder")
                                }

                                Button {
                                    toggleFavorite(resource)
                                } label: {
                                    Label(
                                        resource.isFavorite ? "Unfavorite" : "Favorite",
                                        systemImage: resource.isFavorite ? SFSymbol.Shape.starFill : SFSymbol.Shape.star
                                    )
                                }

                                Divider()

                                Button(role: .destructive) {
                                    deleteResource(resource)
                                } label: {
                                    Label("Delete", systemImage: SFSymbol.Action.trash)
                                }
                            }
                    }
                }
            }
        }
    }

    // MARK: - Selectable Views

    func selectableCard(resource: Resource) -> some View {
        let isSelected = selectedResourceIDs.contains(resource.id)
        return ResourceCard(resource: resource) {
            toggleSelection(resource)
        } onDelete: {
            deleteResource(resource)
        }
        .overlay(alignment: .topLeading) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .padding(8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    func selectableRow(resource: Resource) -> some View {
        let isSelected = selectedResourceIDs.contains(resource.id)
        return HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            ResourceRow(resource: resource)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection(resource)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        )
    }
}
