import SwiftUI

private enum MobileTaskListItem: Identifiable {
    case edge(TaskStatus)
    case header(status: TaskStatus, count: Int)
    case task(TaskItem)

    var id: String {
        switch self {
        case let .edge(status): "edge-\(status.rawValue)"
        case let .header(status, _): "header-\(status.rawValue)"
        case let .task(task): "task-\(task.id.uuidString)"
        }
    }
}

/// What a finished drag means once the drop index is mapped back onto the
/// flat list. Every drag resolves to exactly one of these, so a drop can never
/// land somewhere the store then refuses to honour.
private enum MobileTaskDropIntent {
    case status(TaskStatus)
    case row(UUID)
}

private struct MobileDropFeedback: Equatable {
    var count = 0
    var moved = true
}

struct MobileTaskListScreen: View {
    @ObservedObject var store: TaskStore
    let iCloudAvailability: ICloudAvailability
    let refresh: () async -> Void

    @State private var selectedScope: TaskScope = .tasks
    @State private var editor: MobileTaskEditorConfiguration?
    @State private var searchQuery = ""
    @State private var isSearchPresented = false
    @State private var dropFeedback = MobileDropFeedback()
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let snapshot = store.snapshot(for: selectedScope)
        let sections = filteredSections(snapshot.sections)
        let visibleCount = sections.reduce(0) { $0 + $1.tasks.count }

        VStack(spacing: 0) {
            header(activeCount: snapshot.activeCount)
            scopePicker

            if isSearchPresented {
                searchBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            taskList(sections: sections, visibleCount: visibleCount)

            footer
        }
        .background(Color(uiColor: .systemBackground))
        // Key the list animation to the order the user can actually see. The
        // raw store array is in fetch order, so it reshuffles on every reload
        // and used to animate the whole screen for changes nothing on screen
        // reflects.
        .animation(
            reduceMotion ? nil : PeekabooMotion.spring,
            value: sections.flatMap { $0.tasks.map(\.id) }
        )
        .animation(reduceMotion ? nil : PeekabooMotion.quick, value: selectedScope)
        .animation(reduceMotion ? nil : PeekabooMotion.quick, value: isSearchPresented)
        .animation(reduceMotion ? nil : PeekabooMotion.quick, value: isSearchFocused)
        .sheet(item: $editor) { configuration in
            MobileTaskEditor(store: store, configuration: configuration)
        }
    }

    // MARK: Header

    private func header(activeCount: Int) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Peekaboo")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                HStack(spacing: 5) {
                    Image(systemName: syncSymbol)
                        .font(.system(size: 10, weight: .medium))
                    Text(syncTitle)
                    Text("·")
                    Text(selectedScope.activeSubtitle(count: activeCount))
                        .contentTransition(.numericText())
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .animation(reduceMotion ? nil : PeekabooMotion.quick, value: activeCount)
            }

            Spacer()

            Button(action: toggleSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(
                        Color.primary.opacity(isSearchPresented ? 0.12 : 0.06),
                        in: Circle()
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSearchPresented ? "Close search" : "Search tasks")
            .accessibilityAddTraits(isSearchPresented ? .isSelected : [])
            .accessibilityIdentifier("toggle-task-search")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    // MARK: Scope picker

    private var scopePicker: some View {
        HStack(spacing: 8) {
            ForEach(TaskScope.allCases) { scope in
                scopeCapsule(scope)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-scope-picker")
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search tasks", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 15, design: .rounded))
                .focused($isSearchFocused)
                .submitLabel(.search)
                .accessibilityLabel("Search tasks")
                .accessibilityIdentifier("task-search-field")

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("clear-task-search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(
            Color.primary.opacity(0.05),
            in: Capsule(style: .continuous)
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .onAppear {
            DispatchQueue.main.async { isSearchFocused = true }
        }
    }

    private func toggleSearch() {
        if isSearchPresented {
            closeSearch()
        } else {
            isSearchPresented = true
        }
    }

    private func closeSearch() {
        isSearchFocused = false
        searchQuery = ""
        isSearchPresented = false
    }

    private func scopeCapsule(_ scope: TaskScope) -> some View {
        let isSelected = selectedScope == scope

        return Button {
            guard selectedScope != scope else { return }
            withAnimation(reduceMotion ? nil : PeekabooMotion.quick) {
                selectedScope = scope
            }
        } label: {
            Text(scope.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : Color.secondary)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    Color.primary.opacity(isSelected ? 0.9 : 0.05),
                    in: Capsule(style: .continuous)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(scope.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("task-scope-\(scope.rawValue)")
    }

    // MARK: Task list

    private func taskList(
        sections: [TaskSectionSnapshot],
        visibleCount: Int
    ) -> some View {
        let items = listItems(for: sections)

        return List {
            if visibleCount == 0 {
                emptyState(isSearching: !normalizedSearchQuery.isEmpty)
            } else {
                ForEach(items) { item in
                    switch item {
                    case let .edge(status):
                        edgeDropTarget(status: status)
                    case let .header(status, count):
                        sectionHeader(status: status, count: count)
                    case let .task(task):
                        MobileTaskRow(
                            store: store,
                            task: task,
                            edit: { editor = .edit(task) }
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                    }
                }
                .onMove { source, destination in
                    move(items: items, from: source, to: destination)
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        // A drop that lands somewhere the ordering rules can't represent has to
        // snap back. Say so with a tap instead of letting it read as a glitch.
        .sensoryFeedback(trigger: dropFeedback) { _, feedback in
            feedback.moved ? .impact(weight: .light) : .impact(flexibility: .rigid)
        }
        .scrollIndicators(.never)
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await refresh() }
        .contentMargins(.bottom, isSearchFocused ? 12 : 76, for: .scrollContent)
        .overlay(alignment: .bottom) {
            if !isSearchFocused {
                addTaskButton
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
    }

    private func listItems(for sections: [TaskSectionSnapshot]) -> [MobileTaskListItem] {
        var items = sections.flatMap { section in
            [
                .header(status: section.status, count: section.tasks.count)
            ] + section.tasks.map(MobileTaskListItem.task)
        }
        guard selectedScope == .tasks else { return items }

        items.insert(.edge(.inProgress), at: 0)
        items.append(.edge(.done))
        return items
    }

    /// Headers and edge strips stay movable on purpose. `moveDisabled` also
    /// makes a row undroppable, and List then clamps every proposed drop index
    /// away from it, which puts both out of reach of a drag. Lifting one
    /// instead does nothing: `move` ignores drags that don't start on a task.
    private func sectionHeader(status: TaskStatus, count: Int) -> some View {
        Text("\(status.title) · \(count)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(nil)
            .contentTransition(.numericText())
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 2, trailing: 20))
            .accessibilityIdentifier("task-section-\(status.rawValue)")
    }

    /// Invisible strip past the first and last row. It is the only way to reach
    /// In Progress or Done by drag when those sections are empty, so it needs
    /// to be tall enough to hit with a finger.
    private func edgeDropTarget(status: TaskStatus) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 22)
            .contentShape(Rectangle())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .accessibilityElement()
            .accessibilityLabel("Move to \(status.title)")
            .accessibilityIdentifier("task-edge-\(status.rawValue)")
    }

    private func move(
        items: [MobileTaskListItem],
        from source: IndexSet,
        to destination: Int
    ) {
        guard let sourceIndex = source.first,
              source.count == 1,
              items.indices.contains(sourceIndex),
              case let .task(movedTask) = items[sourceIndex],
              sourceIndex != destination,
              sourceIndex + 1 != destination else { return }

        guard let intent = dropIntent(
            in: items,
            movedTask: movedTask,
            sourceIndex: sourceIndex,
            destination: destination
        ) else { return }

        var moved = false
        withAnimation(reduceMotion ? nil : PeekabooMotion.spring) {
            switch intent {
            case let .status(status):
                moved = store.drop(taskID: movedTask.id, into: status)
            case let .row(targetID):
                moved = store.drop(taskID: movedTask.id, onto: targetID)
            }
        }
        dropFeedback = MobileDropFeedback(count: dropFeedback.count + 1, moved: moved)
    }

    /// `destination` is an insertion index into the pre-move array, so the row
    /// the drop displaces sits one slot earlier when the task travelled down.
    /// Landing on a header or edge zone of the task's own section means "put me
    /// at that end of this section", not "change my status" — the old index
    /// arithmetic read the last slot of the list as the Done edge, which turned
    /// an ordinary drag to the bottom of To Do into a completed task.
    private func dropIntent(
        in items: [MobileTaskListItem],
        movedTask: TaskItem,
        sourceIndex: Int,
        destination: Int
    ) -> MobileTaskDropIntent? {
        // The top strip is a row of its own, so a drop on it resolves to the
        // slot above or below it. Both belong to the strip: the section header
        // sits between it and the first task, so neither slot can mean a
        // reorder. The bottom strip has no such header, so only the slot below
        // it is the strip — the one above is the last row of the last section.
        if case let .edge(status) = items.first, destination <= 1 {
            return edgeIntent(status: status, in: items, movedTask: movedTask, fromTop: true)
        }
        if case let .edge(status) = items.last, destination >= items.count {
            return edgeIntent(status: status, in: items, movedTask: movedTask, fromTop: false)
        }

        let targetIndex = destination > sourceIndex ? destination - 1 : destination
        guard items.indices.contains(targetIndex), targetIndex != sourceIndex else { return nil }

        switch items[targetIndex] {
        case let .task(targetTask):
            return .row(targetTask.id)
        case let .edge(status), let .header(status, _):
            return edgeIntent(
                status: status,
                in: items,
                movedTask: movedTask,
                fromTop: targetIndex < sourceIndex
            )
        }
    }

    /// A drop on a header or edge strip of the task's own section means "put me
    /// at that end of this section", not "change my status" — resolve it to the
    /// row already sitting there so the placement rules stay in one place.
    private func edgeIntent(
        status: TaskStatus,
        in items: [MobileTaskListItem],
        movedTask: TaskItem,
        fromTop: Bool
    ) -> MobileTaskDropIntent? {
        guard status == movedTask.status else { return .status(status) }
        let sectionTasks = items.compactMap { item -> TaskItem? in
            guard case let .task(task) = item, task.status == status else { return nil }
            return task
        }
        guard let anchor = fromTop ? sectionTasks.first : sectionTasks.last,
              anchor.id != movedTask.id else { return nil }
        return .row(anchor.id)
    }

    private var addTaskButton: some View {
        Button {
            editor = .create(selectedScope.creationStatus)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color(uiColor: .systemBackground))
                .frame(width: 60, height: 60)
                .background(Color.primary.opacity(0.9), in: Circle())
                .contentShape(Circle())
                .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selectedScope.newItemTitle)
        .accessibilityIdentifier("add-task-button")
    }

    private func emptyState(isSearching: Bool) -> some View {
        VStack(spacing: 5) {
            Text(isSearching ? "No matches" : selectedScope.emptyStateTitle)
                .font(.system(size: 15, weight: .medium, design: .rounded))
            Text(emptyStateMessage(isSearching: isSearching))
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func filteredSections(_ sections: [TaskSectionSnapshot]) -> [TaskSectionSnapshot] {
        guard !normalizedSearchQuery.isEmpty else { return sections }

        return sections.compactMap { section in
            let matchingTasks = section.tasks.filter {
                $0.title.localizedStandardContains(normalizedSearchQuery)
            }
            guard !matchingTasks.isEmpty else { return nil }
            return TaskSectionSnapshot(status: section.status, tasks: matchingTasks)
        }
    }

    private func emptyStateMessage(isSearching: Bool) -> String {
        if isSearching {
            return "Try a different search."
        }
        return selectedScope == .tasks
            ? "Add a task and it will appear on your Mac too."
            : "Capture an idea and promote it when you're ready."
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        if store.lastErrorMessage != nil || cloudSyncErrorMessage != nil {
            VStack(spacing: 4) {
                if let message = store.lastErrorMessage {
                    Text(message)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }

                if let message = cloudSyncErrorMessage {
                    Text(message)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private var cloudSyncErrorMessage: String? {
        guard case .available = iCloudAvailability else { return nil }
        return store.cloudSyncStatus.lastErrorMessage
    }

    private var syncSymbol: String {
        switch iCloudAvailability {
        case .available: store.cloudSyncStatus.symbolName
        case .checking: "icloud"
        case .noAccount, .restricted, .temporarilyUnavailable, .unavailable:
            "exclamationmark.icloud"
        }
    }

    private var syncTitle: String {
        switch iCloudAvailability {
        case .available: store.cloudSyncStatus.title
        case .checking, .noAccount, .restricted, .temporarilyUnavailable, .unavailable:
            iCloudAvailability.title
        }
    }
}
