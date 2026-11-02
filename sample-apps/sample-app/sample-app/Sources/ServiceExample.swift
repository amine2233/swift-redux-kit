import Foundation
import ReduxKit
import ReduxKitExtensions
import SwiftUI

// MARK: - Service Example: Pomodoro Timer

// This example demonstrates how to use StoreService to feed a store from a source that pushes.
//
// The problem:
// - A timer, a socket, a location monitor or a database observer changes on its own schedule
// - Middleware cannot subscribe to it: `send` runs middleware serially, so a long-lived
//   `for await` inside `process` would block the store forever
// - Wiring a bespoke `.task { for await ... }` per source duplicates the same plumbing every time
//
// The solution:
// - Model the source as a StoreService: one method returning the stream of actions it emits
// - Register it with `services:` next to the reducer and middlewares
// - Start it once with `run()`; cancelling that task tears every service down
//
// Note how the service is dumb: it emits `.tick` every second, always. Whether a tick counts is
// the reducer's decision. Services push facts, reducers decide what they mean.

// MARK: - Pomodoro State & Actions

/// The phase of the pomodoro cycle, each with its own duration.
enum PomodoroPhase: Sendable, Hashable {
    case focus
    case shortBreak
    case longBreak

    /// Number of seconds the phase lasts.
    var duration: Int {
        switch self {
        case .focus:
            25 * 60

        case .shortBreak:
            5 * 60

        case .longBreak:
            15 * 60
        }
    }

    var title: String {
        switch self {
        case .focus:
            "Focus"

        case .shortBreak:
            "Short Break"

        case .longBreak:
            "Long Break"
        }
    }

    var color: Color {
        switch self {
        case .focus:
            .red

        case .shortBreak:
            .green

        case .longBreak:
            .blue
        }
    }
}

/// Pomodoro state
struct PomodoroState: Sendable, Hashable {
    var phase: PomodoroPhase = .focus
    var remaining: Int = PomodoroPhase.focus.duration
    var isRunning: Bool = false
    var completedFocusSessions: Int = 0

    var formattedTime: String {
        String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    var progress: Double {
        1 - Double(remaining) / Double(phase.duration)
    }
}

/// Pomodoro actions
enum PomodoroAction: Actionable {
    /// Emitted by ``PomodoroTimerService`` once per second, whether or not the timer is running.
    case tick
    case start
    case pause
    /// Restarts the current phase.
    case reset
    /// Ends the current phase early, without counting it as completed.
    case skip
}

// MARK: - Reducer

struct PomodoroReducer: Reducer {
    func reduce(oldState: PomodoroState, with action: PomodoroAction) -> PomodoroState {
        var state = oldState

        switch action {
        case .tick:
            // The service ticks unconditionally — the reducer decides whether the tick counts.
            guard state.isRunning else { return state }

            state.remaining -= 1

            if state.remaining <= 0 {
                advance(&state, completed: true)
            }

        case .start:
            state.isRunning = true

        case .pause:
            state.isRunning = false

        case .reset:
            state.isRunning = false
            state.remaining = state.phase.duration

        case .skip:
            advance(&state, completed: false)
        }

        return state
    }

    /// Moves to the next phase: a long break every fourth focus session, a short one otherwise.
    private func advance(_ state: inout PomodoroState, completed: Bool) {
        switch state.phase {
        case .focus:
            if completed {
                state.completedFocusSessions += 1
            }

            state.phase = state.completedFocusSessions.isMultiple(of: 4) && completed
                ? .longBreak
                : .shortBreak

        case .shortBreak, .longBreak:
            state.phase = .focus
        }

        state.remaining = state.phase.duration
    }
}

// MARK: - Service

/// Emits a `.tick` at a fixed interval, for as long as the store runs it.
///
/// Nothing inside the store triggers this: it is an outside source pushing actions in, which is
/// exactly what a `StoreService` is for. The interval is a dependency so tests can shrink it.
struct PomodoroTimerService: StoreService {
    let interval: Duration

    init(interval: Duration = .seconds(1)) {
        self.interval = interval
    }

    func actions() -> AsyncStream<PomodoroAction> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    continuation.yield(.tick)
                }
                continuation.finish()
            }

            // Always release the source when the stream goes away.
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - View

struct ServiceExampleView: View {
    @State private var store = Store(
        initialState: PomodoroState(),
        reducer: PomodoroReducer(),
        middlewares: [],
        services: [PomodoroTimerService()]
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                explanation

                timer

                controls

                sessions
            }
            .padding(24)
        }
        .navigationTitle("Service Example")
        // One line starts every registered service. Leaving the screen cancels this task,
        // which tears the timer down — no unregistering, no deinit bookkeeping.
        .task {
            await store.run()
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("StoreService")
                .font(.headline)

            Text(
                """
                `PomodoroTimerService` emits `.tick` every second, always. The reducer ignores ticks \
                while the timer is paused. Services push facts; reducers decide what they mean.
                """
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var timer: some View {
        VStack(spacing: 16) {
            Text(store.phase.title)
                .font(.headline)
                .foregroundStyle(store.phase.color)

            ZStack {
                Circle()
                    .stroke(store.phase.color.opacity(0.15), lineWidth: 14)

                Circle()
                    .trim(from: 0, to: store.progress)
                    .stroke(store.phase.color, style: .init(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text(store.formattedTime)
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 240, height: 240)
            .animation(.easeInOut, value: store.remaining)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(store.isRunning ? "Pause" : "Start") {
                store.dispatch(store.isRunning ? .pause : .start)
            }
            .buttonStyle(.borderedProminent)
            .tint(store.phase.color)

            Button("Reset") {
                store.dispatch(.reset)
            }
            .buttonStyle(.bordered)

            Button("Skip") {
                store.dispatch(.skip)
            }
            .buttonStyle(.bordered)
        }
    }

    private var sessions: some View {
        HStack(spacing: 8) {
            Text("Completed sessions")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(store.completedFocusSessions)")
                .font(.headline)
                .monospacedDigit()
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        ServiceExampleView()
    }
}
