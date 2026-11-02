import Foundation
import ReduxKit
import ReduxKitExtensions
import SwiftUI

// MARK: - Descriptive Undoable Store Example: Text Editor with Named Undo/Redo

// This example demonstrates how to use DescriptiveUndoableStore to add undo/redo functionality
// with human-readable action descriptions that appear in UI menus.
//
// The problem:
// - Users want to know WHAT they're undoing/redoing
// - Generic "Undo" / "Redo" buttons aren't informative enough
// - Need descriptive labels like "Undo Typing" or "Redo Bold Formatting"
//
// The solution:
// - Actions conform to DescriptiveActionable (provides undoDescription)
// - Wrap Store in DescriptiveUndoableStore
// - Access nextUndoDescription / nextRedoDescription for labels
// - Display undo/redo history with descriptions in menus

// MARK: - Document State & Actions

/// Text document state
struct DocumentState: Sendable, Hashable {
    var text: String = ""
    var title: String = "Untitled"
    var isBold: Bool = false
    var isItalic: Bool = false
    var fontSize: Int = 16
    var wordCount: Int {
        text.split(separator: " ").count
    }
}

/// Document actions with descriptions
enum DocumentAction: DescriptiveActionable {
    case setText(String)
    case appendText(String)
    case setTitle(String)
    case toggleBold
    case toggleItalic
    case increaseFontSize
    case decreaseFontSize
    case setFontSize(Int)
    case clear

    var undoDescription: String {
        switch self {
        case .setText:
            "Typing"
        case let .appendText(text):
            "Insert '\(text.prefix(20))'"
        case .setTitle:
            "Change Title"
        case .toggleBold:
            "Bold Formatting"
        case .toggleItalic:
            "Italic Formatting"
        case .increaseFontSize:
            "Increase Font Size"
        case .decreaseFontSize:
            "Decrease Font Size"
        case .setFontSize:
            "Change Font Size"
        case .clear:
            "Clear Document"
        }
    }
}

/// Document reducer
struct DocumentReducer: Reducer {
    func reduce(oldState: DocumentState, with action: DocumentAction) -> DocumentState {
        var state = oldState

        switch action {
        case let .setText(text):
            state.text = text

        case let .appendText(text):
            state.text += text

        case let .setTitle(title):
            state.title = title

        case .toggleBold:
            state.isBold.toggle()

        case .toggleItalic:
            state.isItalic.toggle()

        case .increaseFontSize:
            state.fontSize = min(state.fontSize + 2, 48)

        case .decreaseFontSize:
            state.fontSize = max(state.fontSize - 2, 8)

        case let .setFontSize(size):
            state.fontSize = max(8, min(size, 48))

        case .clear:
            state.text = ""
        }

        return state
    }
}

// MARK: - SwiftUI Example View

struct DescriptiveUndoableExampleView: View {
    @State private var store = DescriptiveUndoableStore(
        initialState: DocumentState(),
        reducer: DocumentReducer(),
        historyLimit: 100
    )

    @State private var showingUndoMenu = false
    @State private var showingRedoMenu = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with undo/redo menus
            toolbarSection

            Divider()

            // Document editor
            ScrollView {
                editorSection
            }

            Divider()

            // Formatting controls
            formattingSection

            // Explanation
            explanationSection
        }
        .navigationTitle("Descriptive Undo/Redo")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var toolbarSection: some View {
        HStack(spacing: 16) {
            // Undo Menu
            Menu {
                if store.canUndo {
                    Section("Undo History") {
                        ForEach(
                            Array(store.undoDescriptions.prefix(10).enumerated()),
                            id: \.offset
                        ) { index, description in
                            Button {
                                Task {
                                    if index == 0 {
                                        await store.undo()
                                    } else {
                                        await store.undo(steps: index + 1)
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(description)
                                    if index == 0 {
                                        Image(systemName: "arrow.uturn.backward")
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Text("Nothing to Undo")
                        .foregroundStyle(.secondary)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.title3)
                    if let description = store.nextUndoDescription {
                        Text("Undo \(description)")
                            .font(.caption)
                    } else {
                        Text("Undo")
                            .font(.caption)
                    }
                }
            }
            .disabled(!store.canUndo)

            // Redo Menu
            Menu {
                if store.canRedo {
                    Section("Redo History") {
                        ForEach(
                            Array(store.redoDescriptions.enumerated()),
                            id: \.offset
                        ) { index, description in
                            Button {
                                Task {
                                    if index == store.redoCount - 1 {
                                        await store.redo()
                                    } else {
                                        await store.redo(steps: store.redoCount - index)
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(description)
                                    if index == store.redoCount - 1 {
                                        Image(systemName: "arrow.uturn.forward")
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Text("Nothing to Redo")
                        .foregroundStyle(.secondary)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.forward.circle")
                        .font(.title3)
                    if let description = store.nextRedoDescription {
                        Text("Redo \(description)")
                            .font(.caption)
                    } else {
                        Text("Redo")
                            .font(.caption)
                    }
                }
            }
            .disabled(!store.canRedo)

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
                Task {
                    await store.send(.clear)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("Clear")
                }
                .font(.caption)
            }
            .disabled(store.text.isEmpty)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }

    private var editorSection: some View {
        VStack(spacing: 16) {
            // Title
            TextField("Document Title", text: Binding(
                get: { store.title },
                set: { newValue in
                    Task {
                        await store.send(.setTitle(newValue))
                    }
                }
            ))
            .font(.title2)
            .bold()
            .padding()
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Text Editor
            TextEditor(text: Binding(
                get: { store.text },
                set: { newValue in
                    Task {
                        await store.send(.setText(newValue))
                    }
                }
            ))
            .font(.system(size: CGFloat(store.fontSize)))
            .bold(store.isBold)
            .italic(store.isItalic)
            .frame(minHeight: 200)
            .padding(8)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )

            // Quick insert buttons
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Insert")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(["Hello", "World", "Swift", "ReduxKit"], id: \.self) { word in
                        Button {
                            Task {
                                await store.send(.appendText(" \(word)"))
                            }
                        } label: {
                            Text(word)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }

            // Word count
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text("\(store.wordCount) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
    }

    private var formattingSection: some View {
        VStack(spacing: 12) {
            // Text formatting
            HStack(spacing: 12) {
                Button {
                    Task {
                        await store.send(.toggleBold)
                    }
                } label: {
                    Text("B")
                        .font(.headline)
                        .bold()
                        .frame(width: 40, height: 40)
                        .background(store.isBold ? Color.blue : Color.gray.opacity(0.2))
                        .foregroundStyle(store.isBold ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    Task {
                        await store.send(.toggleItalic)
                    }
                } label: {
                    Text("I")
                        .font(.headline)
                        .italic()
                        .frame(width: 40, height: 40)
                        .background(store.isItalic ? Color.blue : Color.gray.opacity(0.2))
                        .foregroundStyle(store.isItalic ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Spacer()

                // Font size
                HStack(spacing: 8) {
                    Button {
                        Task {
                            await store.send(.decreaseFontSize)
                        }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .disabled(store.fontSize <= 8)

                    Text("\(store.fontSize)pt")
                        .font(.caption)
                        .frame(width: 40)

                    Button {
                        Task {
                            await store.send(.increaseFontSize)
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .disabled(store.fontSize >= 48)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How DescriptiveUndoableStore Works:")
                .font(.headline)

            Group {
                Text("• Actions provide undoDescription property")
                Text("• Menus show descriptive labels for each action")
                Text("• Click menu items to undo/redo multiple steps")
                Text("• nextUndoDescription for 'Undo X' labels")
                Text("• undoDescriptions array for full history")
                Text("• Perfect for document editors!")
            }
            .font(.caption)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DescriptiveUndoableExampleView()
    }
}

#Preview("With Content") {
    let store = DescriptiveUndoableStore(
        initialState: DocumentState(
            text: "This is a sample document with some text.\n\nYou can edit it and use undo/redo to navigate through changes.",
            title: "Sample Document",
            isBold: false,
            isItalic: false,
            fontSize: 18
        ),
        reducer: DocumentReducer(),
        historyLimit: 100
    )

    return NavigationStack {
        DescriptiveUndoableExampleView()
            .onAppear {
                // The store is created separately, so this is just for preview
            }
    }
}

// MARK: - Key Takeaways

// 1. DESCRIPTIVE ACTIONABLE PROTOCOL:
//   - Actions must conform to DescriptiveActionable
//   - Requires `var undoDescription: String { get }`
//   - Provides human-readable labels for undo/redo
//
//   Example:
//   ```swift
//   enum DocumentAction: DescriptiveActionable {
//       case setText(String)
//       case toggleBold
//
//       var undoDescription: String {
//           switch self {
//           case .setText:
//               return "Typing"
//           case .toggleBold:
//               return "Bold Formatting"
//           }
//       }
//   }
//   ```
//
// 2. DESCRIPTIVE UNDOABLE STORE FEATURES:
//   - All UndoableStore features PLUS descriptions
//   - nextUndoDescription: What the next undo will do
//   - nextRedoDescription: What the next redo will do
//   - undoDescriptions: Array of all undo descriptions
//   - redoDescriptions: Array of all redo descriptions
//   - undoHistory / redoHistory: Full history with states and actions
//   - undo(steps:) / redo(steps:): Undo/redo multiple at once
//   - undoToIndex(_:): Jump to specific point in history
//
// 3. INITIALIZATION:
//   ```swift
//   let store = DescriptiveUndoableStore(
//       initialState: DocumentState(),
//       reducer: DocumentReducer(),
//       historyLimit: 100
//   )
//   ```
//
// 4. ACCESSING DESCRIPTIONS:
//   ```swift
//   // Next action to undo
//   if let desc = store.nextUndoDescription {
//       Text("Undo \(desc)")  // "Undo Typing"
//   }
//
//   // All undo history
//   ForEach(store.undoDescriptions, id: \.self) { desc in
//       Button("Undo \(desc)") {
//           store.undo()
//       }
//   }
//   ```
//
// 5. UNDO/REDO MENUS:
//   - Show list of actions that can be undone
//   - User can select how far back to undo
//   - Makes undo/redo more discoverable and usable
//   - Standard pattern in document editors
//
// 6. MULTIPLE UNDO/REDO:
//   ```swift
//   // Undo 3 steps at once
//   store.undo(steps: 3)
//
//   // Undo to specific point
//   store.undoToIndex(5)  // Undo to 6th item in history
//   ```
//
// 7. COMMON USE CASES:
//   - Text/code editors (this example)
//   - Spreadsheet applications
//   - Graphic design tools
//   - Form builders
//   - Any app where users want detailed undo history
//
// 8. BENEFITS OVER REGULAR UNDOABLESTORE:
//   - UndoableStore: Generic undo/redo
//   - DescriptiveUndoableStore: Named undo/redo with history
//
//   | Feature | UndoableStore | DescriptiveUndoableStore |
//   |---------|---------------|--------------------------|
//   | Undo/Redo | ✅ | ✅ |
//   | Action descriptions | ❌ | ✅ |
//   | History menus | ❌ | ✅ |
//   | Multi-step undo | Manual | Built-in |
//
// 9. DESCRIPTION BEST PRACTICES:
//   - Keep descriptions short and clear
//   - Use action verbs ("Typing", "Bold", "Delete")
//   - Include context when helpful ("Insert 'Hello'")
//   - Be consistent with naming conventions
//   - Trim long text with .prefix()
//
// 10. EXAMPLE FLOW:
//   User types "Hello"
//   → Dispatches: .setText("Hello")
//   → Stored with description: "Typing"
//
//   User clicks Undo menu
//   → Shows: "Undo Typing"
//   → User clicks it
//   → Text reverts to ""
//
//   User clicks Redo menu
//   → Shows: "Redo Typing"
//   → User clicks it
//   → Text becomes "Hello" again
//
// 11. ADVANCED FEATURES:
//   - Access full HistoryEntry for custom UI
//   - Jump to any point in history
//   - Display visual timeline of changes
//   - Export/import history for debugging
//   - Track who made changes (multi-user)
//
// 12. PERFORMANCE:
//   - Each entry stores full state snapshot
//   - Use historyLimit to control memory
//   - Descriptive strings are lightweight
//   - Consider state size when choosing limit
