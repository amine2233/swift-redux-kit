---
name: reducer-comparable-offset
description: Guide to .comparableOffset(keyPath:prism:comparator:positionInjector:) — applying a reducer to a single array element by index, then re-sorting the array and injecting rank/position metadata into every element.
---

# `.comparableOffset()` — Index-targeted Reducer with Sort and Position Injection

`.comparableOffset(keyPath:prism:comparator:positionInjector:)` lifts a feature reducer so it operates on
**one element in a `[State]` array by its integer index**, then **re-sorts the entire array** and
**injects position metadata** into every element.
It combines what `.sortedOffset()` does (sort) with automatic position tagging.

> **Reducer only** — there is no middleware equivalent of `.comparableOffset()`.

---

## How It Differs from `.sortedOffset()`

| | `.sortedOffset()` | `.comparableOffset()` |
|---|---|---|
| Prism target | `(Int, ChildAction)` | `(Int, ChildAction)` |
| After reduce | Sorts array | Sorts array |
| Position injection | None | Calls `positionInjector(element, index)` on every element |
| State must store rank | No | Yes — State has a rank/position field |
| Use case | Ordered list, no rank display | Leaderboard, ranked list, order-sensitive UI |

> **Use `.sortedOffset()` when elements have no rank field.** Use `.comparableOffset()` when each element must store its position (e.g., `rank`, `order`, `position`).

---

## Anatomy

```
ParentState
  └── players: [Player]                         ← keyPath points here

ParentAction
  └── case updatePlayer(Int, PlayerAction)       ← prism extracts (Int, PlayerAction)

comparator: (Player, Player) -> Bool             ← defines sort order
positionInjector: (Player, Int) -> Player        ← injects 0-based position into every element

PlayerReducer operates on Player with PlayerAction
```

---

## 1. Define the Element Reducer

The element reducer is unaware of sorting or ranking.

```swift
struct PlayerReducer: Reducer {
    struct State: Hashable {
        var id: Int
        var name: String
        var score: Int
        var rank: Int = 0   // populated by positionInjector
    }

    enum Action: Actionable {
        case addPoints(Int)
        case subtractPoints(Int)
    }

    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case let .addPoints(points):    state.score += points
        case let .subtractPoints(points): state.score -= points
        }
        return state
    }
}
```

---

## 2. Define the Parent State & Action

```swift
struct AppReducer: Reducer {
    struct State: Hashable {
        var players: [PlayerReducer.State] = []
    }

    enum Action: Actionable {
        case updatePlayer(Int, PlayerReducer.Action)
    }
}
```

---

## 3. Define the Prism

The prism target is `(Int, ChildAction)` — the same shape as `.offset()` and `.sortedOffset()`.

```swift
extension AppReducer.Action {
    static let updatePlayerPrism = Prism<AppReducer.Action, (Int, PlayerReducer.Action)>(
        embed: { AppReducer.Action.updatePlayer($0, $1) },
        extract: {
            guard case let .updatePlayer(index, action) = $0 else { return nil }
            return (index, action)
        }
    )
}
```

---

## 4. Parent Reducer — Use `.comparableOffset()` with Comparator and Position Injector

```swift
extension AppReducer {
    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState

        switch action {
        case .updatePlayer:
            break   // handled by .comparableOffset() below
        }

        return PlayerReducer()
            .comparableOffset(
                keyPath: \.players,
                prism: Action.updatePlayerPrism,
                comparator: { $0.score > $1.score },        // sort by score descending
                positionInjector: { player, position in
                    var updated = player
                    updated.rank = position + 1             // 0-based → 1-based rank
                    return updated
                }
            )
            .reduce(oldState: state, with: action)
    }
}
```

`.comparableOffset()` automatically:

1. Extracts `(index, ChildAction)` using the prism — returns unchanged state if prism yields `nil`.
2. Returns unchanged state if the index is out of bounds.
3. Applies the element reducer to `array[index]`.
4. Sorts the entire array using the comparator.
5. Calls `positionInjector(element, 0-basedIndex)` on **every** element in the sorted array.
6. Writes the updated, sorted, rank-annotated array back to the key path.

> **Position is 0-based.** Add 1 inside `positionInjector` when the UI expects a 1-based rank.

---

## 5. Multi-criteria Comparator

Combine multiple sort keys to produce a stable ranking.

```swift
PlayerReducer()
    .comparableOffset(
        keyPath: \.players,
        prism: Action.updatePlayerPrism,
        comparator: { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.id < rhs.id          // tie-break by id for stability
        },
        positionInjector: { player, position in
            var p = player
            p.rank = position + 1
            return p
        }
    )
```

---

## 6. Dispatching from the View

```swift
// Give player at current index 0 an extra 50 points
store.dispatch(.updatePlayer(0, .addPoints(50)))
```

> **Index fragility warning:** After the dispatch the array is re-sorted and all indices shift. Always read the current index from the sorted array just before dispatching — never cache it across multiple dispatches.

---

## When NOT to Use `.comparableOffset()`

| Situation | Better approach |
|-----------|-----------------|
| Elements have no rank/position field | `.sortedOffset(keyPath:prism:comparator:)` |
| State is a dictionary (`[Key: State]`) | `.treeComparableKeyed()` from `ReduxKitExtensions` |
| All elements need updating, not just one | Loop in the parent reducer, call `sort(by:)` and inject positions manually |
| Single element targeted by stable ID | `.keyed(keyPath:prism:)` or `.treeKeyed()` |
