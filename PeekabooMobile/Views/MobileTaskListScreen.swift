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

struct MobileTaskListScreen: View {
    @ObservedObject var store: TaskStore
    let iCloudAvailability: ICloudAvailability
    let refresh: () async -> Void

    @State private var selectedScope: TaskScope = .tasks
    @State private var editor: MobileTaskEditorConfiguration?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let snapshot = store.snapshot(for: selectedScope)

        VStack(spacing: 0) {
            header(activeCount: snapshot.activeCount)
            scopePicker

            taskList(snapshot: snapshot)

            footer
        }
        .background(Color(uiColor: .systemBackground))
        .animation(reduceMotion ? nil : PeekabooMotion.spring, value: store.tasks.map(\.id))
        .animation(reduceMotion ? nil : PeekabooMotion.quick, value: selectedScope)
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

    private func taskList(snapshot: TaskScopeSnapshot) -> some View {
        let items = listItems(for: snapshot)

        return List {
            if snapshot.visibleCount == 0 {
                emptyState
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
        .scrollIndicators(.never)
        .refreshable { await refresh() }
        .contentMargins(.bottom, 76, for: .scrollContent)
        .overlay(alignment: .bottom) {
            addTaskButton
                .padding(.bottom, 8)
        }
    }

    private func listItems(for snapshot: TaskScopeSnapshot) -> [MobileTaskListItem] {
        var items = snapshot.sections.flatMap { section in
            [
                .header(status: section.status, count: section.tasks.count)
            ] + section.tasks.map(MobileTaskListItem.task)
        }
        guard selectedScope == .tasks else { return items }

        items.insert(.edge(.inProgress), at: 0)
        items.append(.edge(.done))
        return items
    }

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

    private func edgeDropTarget(status: TaskStatus) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 6)
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
              case let .task(movedTask) = items[sourceIndex] else { return }

        if let status = edgeStatus(in: items, destination: destination) {
            withAnimation(reduceMotion ? nil : PeekabooMotion.spring) {
                _ = store.drop(taskID: movedTask.id, into: status)
            }
            return
        }

        guard sourceIndex != destination,
              sourceIndex + 1 != destination else { return }

        let targetIndex = destination > sourceIndex ? destination - 1 : destination
        guard items.indices.contains(targetIndex), targetIndex != sourceIndex else { return }

        withAnimation(reduceMotion ? nil : PeekabooMotion.spring) {
            switch items[targetIndex] {
            case let .edge(status), let .header(status, _):
                _ = store.drop(taskID: movedTask.id, into: status)
            case let .task(targetTask):
                _ = store.drop(taskID: movedTask.id, onto: targetTask.id)
            }
        }
    }

    private func edgeStatus(
        in items: [MobileTaskListItem],
        destination: Int
    ) -> TaskStatus? {
        guard selectedScope == .tasks else { return nil }
        if destination <= 1 { return .inProgress }
        if destination >= items.count - 1 { return .done }
        return nil
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

    private var emptyState: some View {
        VStack(spacing: 5) {
            Text(selectedScope.emptyStateTitle)
                .font(.system(size: 15, weight: .medium, design: .rounded))
            Text(selectedScope == .tasks
                ? "Add a task and it will appear on your Mac too."
                : "Capture an idea and promote it when you're ready.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
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
