import SwiftUI

struct PeekPanelView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var uiState: PanelUIState
    @ObservedObject var settings: AppSettings

    @State private var searchQuery = ""
    @State private var isSearchPresented = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let snapshot = store.snapshot(for: uiState.selectedScope)
        let sections = filteredSections(snapshot.sections)
        let visibleCount = sections.reduce(0) { $0 + $1.tasks.count }

        VStack(spacing: 0) {
            header(activeCount: snapshot.activeCount)
            scopePicker

            if isSearchPresented {
                searchBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if uiState.isComposerPresented {
                TaskComposerView(store: store, uiState: uiState)
                    .padding(.horizontal, PeekabooStyle.horizontalPadding)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if visibleCount == 0 {
                emptyState(isSearching: !normalizedSearchQuery.isEmpty)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                taskList(sections: sections)
                    .transition(.opacity)
            }

            if let error = store.lastErrorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.horizontal, PeekabooStyle.horizontalPadding)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .peekPanelSurface(translucent: settings.isTranslucent)
        .animation(reduceMotion ? nil : PeekabooMotion.spring, value: uiState.isComposerPresented)
        .animation(reduceMotion ? nil : PeekabooMotion.spring, value: store.tasks.map(\.id))
        .animation(reduceMotion ? nil : PeekabooMotion.quick, value: uiState.selectedScope)
        .animation(reduceMotion ? nil : PeekabooMotion.quick, value: uiState.isDraggingTask)
        .animation(reduceMotion ? nil : PeekabooMotion.quick, value: isSearchPresented)
    }

    private func header(activeCount: Int) -> some View {
        HStack(spacing: 8) {
            Text("Peekaboo")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("· \(activeSubtitle(count: activeCount))")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : PeekabooMotion.quick, value: activeCount)

            Spacer()

            Button(action: toggleSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(
                        Color.primary.opacity(isSearchPresented ? 0.12 : 0.06),
                        in: Circle()
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(isSearchPresented ? "Close search" : "Search tasks")
            .accessibilityLabel(isSearchPresented ? "Close search" : "Search tasks")
            .accessibilityAddTraits(isSearchPresented ? .isSelected : [])
            .accessibilityIdentifier("toggle-task-search")

            Button {
                AppCoordinator.shared.openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings")
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settings-button")

            Button {
                if uiState.isComposerPresented {
                    uiState.endAdding()
                } else {
                    uiState.beginAdding()
                }
            } label: {
                Image(systemName: uiState.isComposerPresented ? "xmark" : "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06), in: Circle())
                    .contentShape(Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(uiState.isComposerPresented ? "Cancel" : newItemTitle)
            .accessibilityLabel(uiState.isComposerPresented ? "Cancel" : newItemTitle)
            .accessibilityIdentifier("add-task-button")
        }
        .padding(.horizontal, PeekabooStyle.horizontalPadding)
        .frame(height: 44)
    }

    private var scopePicker: some View {
        HStack(spacing: 6) {
            ForEach(TaskScope.allCases) { scope in
                scopeCapsule(scope)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PeekabooStyle.horizontalPadding)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-scope-picker")
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search tasks", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .rounded))
                .focused($isSearchFocused)
                .onExitCommand(perform: closeSearch)
                .accessibilityLabel("Search tasks")
                .accessibilityIdentifier("task-search-field")

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("clear-task-search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            Color.primary.opacity(0.045),
            in: Capsule(style: .continuous)
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.6)
        }
        .padding(.horizontal, PeekabooStyle.horizontalPadding)
        .padding(.bottom, 9)
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
        let isSelected = uiState.selectedScope == scope

        return Button {
            selectScope(scope)
        } label: {
            Text(scope.title)
                .font(.system(
                    size: 10,
                    weight: isSelected ? .semibold : .medium,
                    design: .rounded
                ))
                .foregroundStyle(
                    isSelected
                        ? Color(nsColor: .windowBackgroundColor)
                        : Color.secondary
                )
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(
                    Color.primary.opacity(isSelected ? 0.9 : 0.035),
                    in: Capsule(style: .continuous)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(scope.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("task-scope-\(scope.rawValue)")
    }

    private func selectScope(_ scope: TaskScope) {
        guard uiState.selectedScope != scope else { return }
        if reduceMotion {
            uiState.selectScope(scope)
        } else {
            withAnimation(PeekabooMotion.quick) {
                uiState.selectScope(scope)
            }
        }
    }

    private func taskList(sections: [TaskSectionSnapshot]) -> some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                if uiState.isDraggingTask, uiState.selectedScope == .tasks {
                    TaskEdgeDropZone(
                        store: store,
                        uiState: uiState,
                        status: .inProgress
                    )
                }

                ForEach(sections) { section in
                    TaskSectionView(
                        store: store,
                        uiState: uiState,
                        status: section.status,
                        tasks: section.tasks
                    )
                }

                if uiState.isDraggingTask, uiState.selectedScope == .tasks {
                    TaskEdgeDropZone(
                        store: store,
                        uiState: uiState,
                        status: .done
                    )
                }
            }
            .padding(.horizontal, PeekabooStyle.horizontalPadding - 4)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.never)
    }

    private func emptyState(isSearching: Bool) -> some View {
        VStack(spacing: 5) {
            Text(isSearching ? "No matches" : uiState.selectedScope.emptyStateTitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
            Text(emptyStateMessage(isSearching: isSearching))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 18)
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
        return uiState.selectedScope == .tasks
            ? "Add a task and it will stay close by."
            : "Capture an idea for later."
    }

    private func activeSubtitle(count: Int) -> String {
        uiState.selectedScope.activeSubtitle(count: count)
    }

    private var newItemTitle: String {
        uiState.selectedScope.newItemTitle
    }
}

private struct TaskEdgeDropZone: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var uiState: PanelUIState
    let status: TaskStatus

    @State private var isTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 26)
            .contentShape(Rectangle())
            .overlay(alignment: indicatorAlignment) {
                Capsule()
                    .fill(Color.accentColor.opacity(isTargeted ? 0.65 : 0))
                    .frame(height: 2)
                    .padding(.horizontal, 8)
            }
            .onDrop(
                of: [TaskDragPayload.internalTaskType],
                isTargeted: $isTargeted,
                perform: acceptDrop
            )
            .animation(reduceMotion ? nil : PeekabooMotion.quick, value: isTargeted)
            .accessibilityLabel("Move to \(status.title)")
            .accessibilityIdentifier("task-edge-\(status.rawValue)")
    }

    private var indicatorAlignment: Alignment {
        status == .inProgress ? .bottom : .top
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        TaskDragPayload.loadTaskID(from: providers) { taskID in
            uiState.endDragging()
            _ = store.drop(taskID: taskID, into: status)
        }
    }
}
