# SlotMap Primitives

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)
[![CI](https://github.com/swift-primitives/swift-slot-map-primitives/actions/workflows/ci.yml/badge.svg)](https://github.com/swift-primitives/swift-slot-map-primitives/actions/workflows/ci.yml)

`SlotMap<S>` — the generational slot-map column. It is a thin handle discipline over a generational storage column (`S: Store.Protocol & Buffer.Protocol`): inserting yields a **handle** (a slot index paired with a generation), and a handle keeps resolving as long as its slot has not been reused. Remove a slot and its generation bumps, so a stale handle to a since-reused slot is **detected**, not silently misread — the classic fix for the ABA / dangling-index problem in index-based containers.

The ADT is a handle discipline only; it carries no `deinit` (teardown lives in the underlying column's oracle or the shared box's drain). The backing may be a move-only generational column or a `Shared` CoW column.

---

## Key Features

- **Stable handles** — an insert returns a handle that survives other inserts and removals; no index invalidation on mutation.
- **Generational safety** — a removed-then-reused slot bumps its generation, so stale handles resolve to `nil` instead of the wrong element.
- **Column-agnostic** — built over any generational `Store.Protocol & Buffer.Protocol` column, move-only or `Shared`.
- **No teardown of its own** — a pure handle discipline; lifecycle stays in the backing column.

---

## Quick Start

```swift
import SlotMap_Primitive

// Insert returns a stable, generation-checked handle:
var map = SlotMap(/* generational column */)
let handle = map.insert(value)
// ... other inserts/removes ...
let still = map[handle]   // resolves iff the slot wasn't reused
```

---

## Installation

Add the dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/swift-primitives/swift-slot-map-primitives.git", branch: "main")
]
```

Add a product to your target:

```swift
.target(
    name: "App",
    dependencies: [
        .product(name: "SlotMap Primitives", package: "swift-slot-map-primitives")
    ]
)
```

The package is pre-1.0 — depend on `branch: "main"` until `0.1.0` is tagged. Requires Swift 6.3 and macOS 26 / iOS 26 / tvOS 26 / watchOS 26 / visionOS 26 (or the corresponding Linux / Windows toolchain).

---

## Architecture

| Product | Contents | When to import |
|---------|----------|----------------|
| `SlotMap Primitives` | Umbrella — re-exports the type | Most consumers |
| `SlotMap Primitive` | `SlotMap<S>` — the generational handle discipline | Naming the type directly |

---

## Platform Support

| Platform         | CI  | Status       |
|------------------|-----|--------------|
| macOS 26         | Yes | Full support |
| Linux            | Yes | Full support |
| Windows          | Yes | Full support |
| iOS/tvOS/watchOS | —   | Supported    |
| Swift Embedded   | —   | Pending (nightly-toolchain follow-up) |

---

## Related Packages

- [`swift-storage-arena-primitives`](https://github.com/swift-primitives/swift-storage-arena-primitives) — `Storage.Generational`, the generational substrate behind a slot map.
- [`swift-store-primitives`](https://github.com/swift-primitives/swift-store-primitives) — `Store.Protocol`, the column capability `SlotMap` is built over.
- [`swift-shared-primitives`](https://github.com/swift-primitives/swift-shared-primitives) — `Shared`, an optional CoW backing for a slot map.

---

## Community

<!-- BEGIN: discussion -->
<!-- END: discussion -->

## License

Apache 2.0. See [LICENSE.md](LICENSE.md).
