import SwiftUI
import CoreData

// The Files list's changes: a card's menu, the bulk actions of select mode,
// and the sheets and alerts they open.
extension FilesLibrary {

    // MARK: - A card's menu

    @ViewBuilder
    func cardMenu(for resource: CDResource) -> some View {
        Button {
            openResource(resource)
        } label: {
            Label("Open", systemImage: "arrow.up.forward.square")
        }
        Button {
            printResource(resource)
        } label: {
            Label("Print", systemImage: "printer")
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
            ResourceDeletion.delete([resource], context: viewContext, saveCoordinator: dependencies.saveCoordinator)
        } label: {
            Label("Delete", systemImage: SFSymbol.Action.trash)
        }
    }

    /// Opens the resource's file (Share on iPhone and iPad).
    private func openResource(_ resource: CDResource) {
        ResourceDocumentActions.open(resource) { report($0, for: resource) }
    }

    private func printResource(_ resource: CDResource) {
        ResourceDocumentActions.print(resource) { report($0, for: resource) }
    }

    /// A file that opened is stamped as viewed, so Recents lists it as the
    /// detail screen's does; one that isn't there says so instead of
    /// opening to nothing.
    private func report(_ outcome: ResourceDocumentActions.Outcome, for resource: CDResource) {
        switch outcome {
        case .shown:
            resource.lastViewedAt = Date()
            dependencies.saveCoordinator.save(viewContext, reason: "Resource opened")
        case .fileMissing:
            dependencies.toastService.showError(AppErrorMessages.resourceFileUnavailable)
        case .notShown:
            break
        }
    }

    private func toggleFavorite(_ resource: CDResource) {
        resource.isFavorite.toggle()
        resource.modifiedAt = Date()
        dependencies.saveCoordinator.save(viewContext, reason: "Toggle favorite")
    }

    // MARK: - Select mode

    func exitSelectMode() {
        isSelectMode = false
        selectedObjectIDs.removeAll()
    }

    func bulkToggleFavorite() {
        let resources = selectedResources
        let allFavorited = resources.allSatisfy(\.isFavorite)
        for resource in resources {
            resource.isFavorite = !allFavorited
            resource.modifiedAt = Date()
        }
        dependencies.saveCoordinator.save(viewContext, reason: "Toggle favorites")
    }

    private func bulkSetCategory(_ category: ResourceCategory) {
        for resource in selectedResources {
            resource.category = category
            resource.modifiedAt = Date()
        }
        dependencies.saveCoordinator.save(viewContext, reason: "Update resource category")
    }

    private func bulkAddTags(_ tags: [String]) {
        for resource in selectedResources {
            for tag in tags {
                let tagName = TagHelper.tagName(tag).lowercased()
                if !resource.tagsArray.contains(where: { TagHelper.tagName($0).lowercased() == tagName }) {
                    resource.tagsArray.append(tag)
                }
            }
            resource.modifiedAt = Date()
        }
        dependencies.saveCoordinator.save(viewContext, reason: "Add resource tags")
    }

    private func bulkDelete() {
        ResourceDeletion.delete(selectedResources, context: viewContext, saveCoordinator: dependencies.saveCoordinator)
        exitSelectMode()
    }

    // MARK: - Sheets and alerts

    func attachSheets(to content: some View) -> some View {
        content
            .sheet(isPresented: $isShowingImportSheet) {
                ResourceImportSheet()
            }
            .sheet(isPresented: $isShowingBulkCategoryPicker) {
                bulkCategorySheet
            }
            .sheet(isPresented: $isShowingBulkTagPicker) {
                bulkTagSheet
            }
            .sheet(item: $resourceToRecategorize) { resource in
                recategorizeSheet(for: resource)
            }
            .alert("Rename File", isPresented: Binding(
                get: { resourceToRename != nil },
                set: { if !$0 { resourceToRename = nil } }
            )) {
                TextField("Title", text: $renameText)
                Button("Cancel", role: .cancel) {
                    resourceToRename = nil
                }
                Button("Save") {
                    let title = renameText.trimmingCharacters(in: .whitespaces)
                    if let resource = resourceToRename, !title.isEmpty {
                        resource.title = title
                        resource.modifiedAt = Date()
                        dependencies.saveCoordinator.save(viewContext, reason: "Rename resource")
                    }
                    resourceToRename = nil
                }
            }
            .confirmationDialog(
                "Delete \(selectedCount) File\(selectedCount == 1 ? "" : "s")?",
                isPresented: $isShowingBulkDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    bulkDelete()
                }
            } message: {
                Text("This permanently deletes the selected files.")
            }
    }

    private var bulkCategorySheet: some View {
        categoryList(title: "Set Category", current: nil) { category in
            bulkSetCategory(category)
            isShowingBulkCategoryPicker = false
        } onCancel: {
            isShowingBulkCategoryPicker = false
        }
    }

    private func recategorizeSheet(for resource: CDResource) -> some View {
        categoryList(title: "Change Category", current: resource.category) { category in
            resource.category = category
            resource.modifiedAt = Date()
            dependencies.saveCoordinator.save(viewContext, reason: "Update resource category")
            resourceToRecategorize = nil
        } onCancel: {
            resourceToRecategorize = nil
        }
    }

    /// The category list both Categorize and Change Category pick from.
    private func categoryList(
        title: String,
        current: ResourceCategory?,
        onPick: @escaping (ResourceCategory) -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        NavigationStack {
            List {
                ForEach(ResourceCategory.allCases) { category in
                    Button {
                        onPick(category)
                    } label: {
                        HStack {
                            Label(category.rawValue, systemImage: category.icon)
                                .foregroundStyle(.primary)
                            Spacer()
                            if current == category {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 300, minHeight: 400)
        #endif
    }

    private var bulkTagSheet: some View {
        NavigationStack {
            Form {
                Section("Add Tags to \(selectedCount) File\(selectedCount == 1 ? "" : "s")") {
                    TagPicker(selectedTags: $bulkTags)
                }
            }
            .navigationTitle("Add Tags")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingBulkTagPicker = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        bulkAddTags(bulkTags)
                        isShowingBulkTagPicker = false
                    }
                    .disabled(bulkTags.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }
}
