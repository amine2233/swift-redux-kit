import ReduxKit
import ReduxKitTesting
import Testing
@testable import sample_app

// Tests for the service example (`PomodoroState` / `PomodoroAction` / `PomodoroReducer` /
// `PomodoroTimerService`) using the `ReduxKitTesting` package.

@MainActor
struct PomodoroTests {
    // MARK: - Reducer (synchronous, isolated)

    @Test
    func tickIsIgnoredWhilePaused() {
        expectReduce(
            PomodoroReducer(),
            from: PomodoroState(remaining: 100, isRunning: false),
            action: .tick,
            to: PomodoroState(remaining: 100, isRunning: false)
        )
    }

    @Test
    func tickCountsDownWhileRunning() {
        PomodoroReducer().probe(PomodoroState(remaining: 100, isRunning: true))
            .send(.tick)
            .expect { #expect($0.remaining == 99) }
            .send(.tick)
            .expect { #expect($0.remaining == 98) }
    }

    @Test
    func finishingFocusStartsAShortBreakAndCountsTheSession() {
        PomodoroReducer().probe(PomodoroState(phase: .focus, remaining: 1, isRunning: true))
            .send(.tick)
            .expect {
                #expect($0.phase == .shortBreak)
                #expect($0.remaining == PomodoroPhase.shortBreak.duration)
                #expect($0.completedFocusSessions == 1)
            }
    }

    @Test
    func everyFourthFocusSessionStartsALongBreak() {
        PomodoroReducer().probe(
            PomodoroState(phase: .focus, remaining: 1, isRunning: true, completedFocusSessions: 3)
        )
        .send(.tick)
        .expect {
            #expect($0.phase == .longBreak)
            #expect($0.completedFocusSessions == 4)
        }
    }

    @Test
    func skippingEndsThePhaseWithoutCountingIt() {
        PomodoroReducer().probe(PomodoroState(phase: .focus, remaining: 900, isRunning: true))
            .send(.skip)
            .expect {
                #expect($0.phase == .shortBreak)
                #expect($0.completedFocusSessions == 0)
            }
    }

    // MARK: - Service (isolated)

    @Test
    func timerServiceEmitsTicks() async {
        var received: [PomodoroAction] = []

        for await action in PomodoroTimerService(interval: .milliseconds(1)).actions() {
            received.append(action)
            if received.count == 3 { break }
        }

        #expect(received == [.tick, .tick, .tick])
    }

    // MARK: - Store (full integration)

    @Test
    func ticksFromTheServiceReachTheStore() async {
        // Drive the ticks from the test instead of registering the real timer: the assertions stay
        // deterministic and the test does not wait on wall-clock seconds.
        let (ticks, continuation) = AsyncStream.makeStream(of: PomodoroAction.self)
        let store = TestStore(
            initialState: PomodoroState(remaining: 100, isRunning: true),
            reducer: PomodoroReducer(),
            middlewares: [],
            services: [ClosureService { ticks }]
        )

        let task = Task { await store.run() }
        continuation.yield(.tick)
        continuation.yield(.tick)
        continuation.finish()
        // Awaiting the run is what guarantees every emitted tick is in the log.
        await task.value

        await store.receive(.tick) { $0.remaining = 99 }
        await store.receive(.tick) { $0.remaining = 98 }

        store.finish()
    }

    @Test
    func pausingStopsTheStoreFromConsumingTicks() async {
        let (ticks, continuation) = AsyncStream.makeStream(of: PomodoroAction.self)
        let store = TestStore(
            initialState: PomodoroState(remaining: 100, isRunning: true),
            reducer: PomodoroReducer(),
            middlewares: [],
            services: [ClosureService { ticks }]
        )

        await store.send(.pause) { $0.isRunning = false }

        let task = Task { await store.run() }
        continuation.yield(.tick)
        continuation.finish()
        await task.value

        // The service still emitted — the reducer simply left the state alone.
        await store.receive(.tick)

        store.finish()
    }
}
