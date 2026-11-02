import Foundation
import ReduxKit
import ReduxKitExtensions
import SwiftUI

// MARK: - Undoable Store Example: Drawing Canvas with Undo/Redo

// This example demonstrates how to use UndoableStore to add undo/redo functionality
// to your Redux state management.
//
// The problem:
// - Users want to undo/redo their actions
// - Manually tracking state history is complex and error-prone
// - Need to handle history limits and state snapshots
//
// The solution:
// - Wrap your Store in UndoableStore
// - UndoableStore automatically tracks state changes
// - Call undo() and redo() to navigate history
// - Use beginGrouping() to group multiple actions
// - Configure history limit to control memory usage

// MARK: - Canvas State & Actions

/// Drawing point on the canvas
struct DrawingPoint: Sendable, Hashable, Identifiable {
    let id: UUID
    let x: Double
    let y: Double
    let color: Color
    let size: Double

    init(id: UUID = UUID(), x: Double, y: Double, color: Color = .black, size: Double = 3.0) {
        self.id = id
        self.x = x
        self.y = y
        self.color = color
        self.size = size
    }
}

/// Drawing stroke (collection of points)
struct DrawingStroke: Sendable, Hashable, Identifiable {
    let id: UUID
    var points: [DrawingPoint]
    let color: Color
    let size: Double

    init(id: UUID = UUID(), points: [DrawingPoint] = [], color: Color = .black, size: Double = 3.0) {
        self.id = id
        self.points = points
        self.color = color
        self.size = size
    }
}

/// Canvas state
struct CanvasState: Sendable, Hashable {
    var strokes: [DrawingStroke] = []
    var currentColor: Color = .black
    var currentSize: Double = 3.0
    var backgroundColor: Color = .white

    var isEmpty: Bool {
        strokes.isEmpty
    }

    var totalPoints: Int {
        strokes.reduce(0) { $0 + $1.points.count }
    }
}

/// Canvas actions
enum CanvasAction: Actionable {
    case startStroke(x: Double, y: Double)
    case addPoint(x: Double, y: Double)
    case endStroke
    case clear
    case setColor(Color)
    case setSize(Double)
    case setBackgroundColor(Color)
    case removeStroke(UUID)
}

/// Canvas reducer
struct CanvasReducer: Reducer {
    func reduce(oldState: CanvasState, with action: CanvasAction) -> CanvasState {
        var state = oldState

        switch action {
        case let .startStroke(x, y):
            let point = DrawingPoint(x: x, y: y, color: state.currentColor, size: state.currentSize)
            let stroke = DrawingStroke(points: [point], color: state.currentColor, size: state.currentSize)
            state.strokes.append(stroke)

        case let .addPoint(x, y):
            guard !state.strokes.isEmpty else { return state }

            let point = DrawingPoint(x: x, y: y, color: state.currentColor, size: state.currentSize)
            state.strokes[state.strokes.count - 1].points.append(point)

        case .endStroke:
            // Stroke is already in the array, just marking it as complete
            break

        case .clear:
            state.strokes.removeAll()

        case let .setColor(color):
            state.currentColor = color

        case let .setSize(size):
            state.currentSize = size

        case let .setBackgroundColor(color):
            state.backgroundColor = color

        case let .removeStroke(id):
            state.strokes.removeAll { $0.id == id }
        }

        return state
    }
}

// MARK: - SwiftUI Example View

struct UndoableExampleView: View {
    @State private var store = UndoableStore(
        initialState: CanvasState(),
        reducer: CanvasReducer(),
        historyLimit: 50 // Keep last 50 states
    )

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbarSection

            Divider()

            // Canvas
            canvasSection

            Divider()

            ScrollView {
                // Controls
                controlsSection

                // Explanation
                explanationSection
            }
        }
        .navigationTitle("Undoable Example: Canvas")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var toolbarSection: some View {
        HStack(spacing: 16) {
            // Undo/Redo
            HStack(spacing: 8) {
                Button {
                    store.undoDispatch()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title3)
                }
                .disabled(!store.canUndo)

                Button {
                    store.redoDispatch()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.title3)
                }
                .disabled(!store.canRedo)
            }

            Divider()
                .frame(height: 30)

            // Stats
            VStack(alignment: .leading, spacing: 2) {
                Text("Undo: \(store.undoCount)")
                    .font(.caption2)
                Text("Redo: \(store.redoCount)")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)

            Spacer()

            // Clear
            Button {
                store.dispatch(.clear)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("Clear")
                }
                .font(.caption)
            }
            .disabled(store.isEmpty)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }

    private var canvasSection: some View {
        CanvasView(store: store)
            .frame(height: 400)
            .background(store.backgroundColor)
            .border(Color.gray.opacity(0.3), width: 1)
    }

    private var controlsSection: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Color picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Brush Color")
                        .font(.headline)

                    HStack(spacing: 12) {
                        ForEach(
                            [Color.black, .red, .blue, .green, .orange, .purple, .pink],
                            id: \.self
                        ) { color in
                            ColorButton(
                                color: color,
                                isSelected: store.currentColor == color
                            ) {
                                store.dispatch(.setColor(color))
                            }
                        }
                    }
                }

                // Size slider
                VStack(alignment: .leading, spacing: 8) {
                    Text("Brush Size: \(Int(store.currentSize))")
                        .font(.headline)

                    Slider(value: Binding(
                        get: { store.currentSize },
                        set: { newValue in
                            Task {
                                await store.send(.setSize(newValue))
                            }
                        }
                    ), in: 1 ... 20, step: 1)
                }

                // Background color
                VStack(alignment: .leading, spacing: 8) {
                    Text("Background Color")
                        .font(.headline)

                    HStack(spacing: 12) {
                        ForEach(
                            [Color.white, .black, .gray.opacity(0.2), .blue.opacity(0.1)],
                            id: \.self
                        ) { color in
                            ColorButton(
                                color: color,
                                isSelected: store.backgroundColor == color,
                                showBorder: true
                            ) {
                                Task {
                                    await store.send(.setBackgroundColor(color))
                                }
                            }
                        }
                    }
                }

                // Stats
                HStack(spacing: 20) {
                    StatBadge(label: "Strokes", value: "\(store.strokes.count)")
                    StatBadge(label: "Points", value: "\(store.totalPoints)")
                }
            }
            .padding()
        }
        .frame(maxHeight: 250)
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How UndoableStore Works:")
                .font(.headline)

            Group {
                Text("• Wraps regular Store with undo/redo")
                Text("• Automatically tracks state changes")
                Text("• Call .undo() to go back")
                Text("• Call .redo() to go forward")
                Text("• historyLimit: 50 (keeps last 50 states)")
                Text("• Color/size changes are undoable too!")
            }
            .font(.caption)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
    }
}

// MARK: - Canvas View

private struct CanvasView: View {
    let store: UndoableStore<CanvasState, CanvasAction>

    var body: some View {
        Canvas { context, _ in
            // Draw all strokes
            for stroke in store.strokes {
                var path = Path()

                guard let firstPoint = stroke.points.first else { continue }

                path.move(to: CGPoint(x: firstPoint.x, y: firstPoint.y))

                for point in stroke.points.dropFirst() {
                    path.addLine(to: CGPoint(x: point.x, y: point.y))
                }

                context.stroke(
                    path,
                    with: .color(stroke.color),
                    lineWidth: stroke.size
                )
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let location = value.location

                    if value.translation == .zero {
                        // Start new stroke
                        store.dispatch(.startStroke(x: location.x, y: location.y))
                    } else {
                        // Continue stroke
                        store.dispatch(.addPoint(x: location.x, y: location.y))
                    }
                }
                .onEnded { _ in
                    store.dispatch(.endStroke)
                }
        )
    }
}

// MARK: - Supporting Views

private struct ColorButton: View {
    let color: Color
    let isSelected: Bool
    var showBorder: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 40, height: 40)
                .overlay(
                    Circle()
                        .strokeBorder(showBorder ? Color.gray : Color.clear, lineWidth: 1)
                )
                .overlay(
                    Circle()
                        .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                )
        }
    }
}

private struct StatBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .bold()

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        UndoableExampleView()
    }
}

#Preview("With Drawing") {
    let store = UndoableStore(
        initialState: CanvasState(
            strokes: [
                DrawingStroke(
                    id: UUID(1),
                    points: [
                        DrawingPoint(id: UUID(), x: 50, y: 50, color: .black, size: 3),
                        DrawingPoint(id: UUID(), x: 100, y: 100, color: .black, size: 3),
                        DrawingPoint(id: UUID(), x: 150, y: 50, color: .black, size: 3)
                    ],
                    color: .black,
                    size: 3
                )
            ],
            currentColor: .red,
            currentSize: 5.0
        ),
        reducer: CanvasReducer(),
        historyLimit: 50
    )

    return NavigationStack {
        UndoableExampleView()
            .onAppear {
                // Need to inject the store somehow - for now just showing the concept
            }
    }
}

// MARK: - Key Takeaways

// 1. UNDOABLE STORE PURPOSE:
//   - Adds automatic undo/redo functionality to Redux stores
//   - Tracks history of state changes
//   - Allows navigation through previous states
//
// 2. UNDOABLE STORE FEATURES:
//   - undo(): Go back to previous state
//   - redo(): Go forward to next state
//   - canUndo / canRedo: Check if operations available
//   - undoCount / redoCount: Number of states in history
//   - clearHistory(): Remove all history
//   - beginGrouping(): Group next action with previous (no new history)
//   - historyLimit: Limit number of states kept (0 = unlimited)
//
// 3. INITIALIZATION:
//   Option 1 - Wrap existing store:
//   ```
//   let store = Store(initialState:reducer:middlewares:)
//   let undoableStore = UndoableStore(store: store, historyLimit: 50)
//   ```
//
//   Option 2 - Create directly:
//   ```
//   let undoableStore = UndoableStore(
//       initialState: CanvasState(),
//       reducer: CanvasReducer(),
//       historyLimit: 50
//   )
//   ```
//
// 4. HOW IT WORKS:
//   - UndoableStore wraps a regular Store
//   - Before each action, saves current state to "past" array
//   - After action, clears "future" array (can't redo after new action)
//   - undo(): Moves current → future, restores from past
//   - redo(): Moves current → past, restores from future
//   - Uses Store.setState() to restore without running reducer
//
// 5. MEMORY MANAGEMENT:
//   - historyLimit: 0 = unlimited (watch memory!)
//   - historyLimit: N = keep last N states
//   - Each state is a full snapshot (use immutable structs)
//   - clearHistory() to free memory when needed
//
// 6. GROUPING ACTIONS:
//   - beginGrouping() makes next action not create history
//   - Useful for continuous updates (e.g., slider dragging)
//   - Example:
//   ```
//   store.beginGrouping()
//   await store.send(.setSize(5))  // Won't create undo point
//   await store.send(.setColor(.red))  // Normal undo point
//   ```
//
// 7. COMMON USE CASES:
//   - Drawing/painting apps
//   - Text editors
//   - Form builders
//   - Game level editors
//   - Configuration tools
//   - Any app where users want to undo actions
//
// 8. SWIFTUI INTEGRATION:
//   - Use @State private var store = UndoableStore(...)
//   - Access state: store.propertyName (via @dynamicMemberLookup)
//   - Send actions: await store.send(.action)
//   - Undo/Redo buttons: .disabled(!store.canUndo)
//
// 9. WHEN TO USE:
//   - Use UndoableStore when:
//     * Users need undo/redo functionality
//     * State changes should be reversible
//     * You want automatic history tracking
//
//   - Don't use when:
//     * Undo/redo not needed
//     * State is very large (memory concerns)
//     * Need custom undo behavior (implement manually)
//
// 10. BEST PRACTICES:
//   - Set reasonable historyLimit (10-100 typically)
//   - Use immutable state (structs, not classes)
//   - Don't store huge data in state (use references)
//   - Clear history when starting new document/session
//   - Consider grouping rapid updates (slider, drag)
//
// 11. EXAMPLE FLOW:
//   User draws a stroke
//   → Dispatches: .startStroke, .addPoint, .addPoint, .endStroke
//   → Each action saves state to history
//   → User clicks Undo
//   → UndoableStore restores previous state
//   → Canvas shows state before last stroke
//   → User clicks Redo
//   → UndoableStore restores next state
//   → Canvas shows stroke again
