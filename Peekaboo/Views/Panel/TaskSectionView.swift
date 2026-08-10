import SwiftUI
import UniformTypeIdentifiers

struct TaskSectionView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var uiState: PanelUIState
    let status: TaskStatus
    let tasks: [TaskItem]

    @State private var isDropTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Text("\(status.title) · \(tasks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("task-section-\(status.rawValue)")
                Spacer()
            }
            .frame(height: 24)
            .padding(.horizontal, 4)

            VStack(spacing: PeekabooStyle.taskSpacing) {
                ForEach(tasks) { task in
                    TaskRowView(store: store, uiState: uiState, task: task)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .scale(scale: 0.96).combined(with: .opacity)
                            )
                        )
                }
            }
        }
        .background(
            Color.accentColor.opacity(isDropTargeted ? 0.08 : 0),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .onDrop(of: [TaskDragPayload.internalTaskType], isTargeted: $isDropTargeted) { providers, _ in
            acceptSectionDrop(from: providers)
        }
        .animation(reduceMotion ? nil : PeekabooMotion.quick, value: isDropTargeted)
        .animation(reduceMotion ? nil : PeekabooMotion.spring, value: tasks.map(\.id))
    }

    private func acceptSectionDrop(from providers: [NSItemProvider]) -> Bool {
        TaskDragPayload.loadTaskID(from: providers) { draggedTaskID in
            uiState.endDragging()
            _ = store.drop(taskID: draggedTaskID, into: status)
        }
    }
}
