// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-primitives open source project
//
// Copyright (c) 2024-2026 Coen ten Thije Boonkkamp and the swift-primitives project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

import SlotMap_Primitives
import Storage_Generational_Primitives
import Storage_Primitive
import Store_Primitive
import Buffer_Primitive
import Memory_Heap_Primitives
import Memory_Allocator_Primitive
import Shared_Primitive
import Index_Primitives
import Tagged_Primitives_Standard_Library_Integration
import Ordinal_Primitives
import Ordinal_Primitives_Standard_Library_Integration
import Cardinal_Primitives

// The ratified columns, spelled as the package's own test suite spells them
// (front doors per [DS-028] — `Slots<E>` is exactly the canonical front door's
// pinned column, so `MoveMap<E>` is `SlotMap<E>` directly; `CoWMap<E>` is the
// `.Shared` ownership variant).

typealias Slots<E: ~Copyable> =
    Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>

typealias MoveMap<E: ~Copyable> = SlotMap<E>

typealias CoWMap<E: ~Copyable> = SlotMap<E>.Shared

extension Bench {
    /// The inventory rows: handle-validation overhead per access (the
    /// `_generations` read — the arc-5 SoA gate input at WRAPPER level;
    /// the arena bench triangulates the substrate level), insert/remove
    /// vs the array-baseline class, and occupied-iteration including the
    /// hole-skipping cost (`_occupied` scan).
    ///
    /// `access.valid`: withElement over a precomputed live-handle stream —
    ///   per-access = generation check + slot read. Baselines: stdlib [Int]
    ///   subscript over an index stream (no validation — the delta IS the
    ///   ledger cost) and Swift.Dictionary<Int,Int> keyed read (the stable-
    ///   key map consumers otherwise reach for).
    /// `access.stale`: contains() over removed handles — the validation
    ///   failure branch.
    /// `insertRemove.cycle`: steady-state insert+remove pairs (free-list
    ///   slot reuse) vs Dictionary rolling-key insert/remove.
    /// `iterate.full` / `iterate.holes`: forEach at full occupancy and at
    ///   half-holes (insert 2n, remove odd handles → n live of 2n slots).
    /// `insert.zero`: build n from slotCapacity 0 (growth door).
    static func slotMapCases() -> [Result] {
        var results: [Result] = []

        for n in sizes {
            let passes = Swift.max(1, (elementOpsTarget / 4) / n)
            let ops = passes * n
            let seed = opaque(1)

            // setup: live maps + handle streams (outside timed regions)
            var m = MoveMap<Int>(slotCapacity: Index<Int>.Count(UInt(n)))
            var liveHandles: [Store.Generational.Handle] = []
            liveHandles.reserveCapacity(n)
            for i in 0..<n { liveHandles.append(m.insert(i &+ seed)) }

            var c = CoWMap<Int>(slotCapacity: Index<Int>.Count(UInt(n)))
            var cowHandles: [Store.Generational.Handle] = []
            cowHandles.reserveCapacity(n)
            for i in 0..<n { cowHandles.append(c.insert(i &+ seed)) }

            var sa: [Int] = []
            sa.reserveCapacity(n)
            for i in 0..<n { sa.append(i &+ seed) }
            let ints = [Int](0..<n)

            var sd = Swift.Dictionary<Int, Int>(minimumCapacity: n)
            for i in 0..<n { sd[i] = i &+ seed }

            results.append(Result(
                name: "access.valid", subject: "tower.direct", n: n, opsPerBatch: ops,
                perOpNs: sample(opsPerBatch: ops) {
                    var sum = 0
                    for _ in 0..<passes {
                        for h in liveHandles { sum &+= m.withElement(at: h) { $0 } }
                    }
                    sink(sum)
                }
            ))

            results.append(Result(
                name: "access.valid", subject: "tower.cow", n: n, opsPerBatch: ops,
                perOpNs: sample(opsPerBatch: ops) {
                    var sum = 0
                    for _ in 0..<passes {
                        for h in cowHandles { sum &+= c.withElement(at: h) { $0 } }
                    }
                    sink(sum)
                }
            ))

            results.append(Result(
                name: "access.valid", subject: "stdlib.array", n: n, opsPerBatch: ops,
                perOpNs: sample(opsPerBatch: ops) {
                    var sum = 0
                    for _ in 0..<passes {
                        for i in ints { sum &+= sa[i] }
                    }
                    sink(sum)
                }
            ))

            results.append(Result(
                name: "access.valid", subject: "stdlib.dictionary", n: n, opsPerBatch: ops,
                perOpNs: sample(opsPerBatch: ops) {
                    var sum = 0
                    for _ in 0..<passes {
                        for i in ints { sum &+= sd[i] ?? 0 }
                    }
                    sink(sum)
                }
            ))

            // stale handles: a parallel map whose entries were all removed
            var staleMap = MoveMap<Int>(slotCapacity: Index<Int>.Count(UInt(n)))
            var staleHandles: [Store.Generational.Handle] = []
            staleHandles.reserveCapacity(n)
            for i in 0..<n { staleHandles.append(staleMap.insert(i)) }
            for h in staleHandles { _ = staleMap.remove(h) }
            for i in 0..<n { _ = staleMap.insert(i &+ seed) }   // slots reused → generations advanced

            results.append(Result(
                name: "access.stale", subject: "tower.direct", n: n, opsPerBatch: ops,
                perOpNs: sample(opsPerBatch: ops) {
                    var alive = 0
                    for _ in 0..<passes {
                        for h in staleHandles where staleMap.contains(h) { alive &+= 1 }
                    }
                    sink(alive)
                }
            ))

            let pairs = Swift.max(1, (elementOpsTarget / 8))
            let pairOps = pairs * 2

            // remove-then-insert through a handle ring (occupancy stays n;
            // the substrate has no auto-growth and fatals on exhaustion).
            var ring = liveHandles
            var cursor = 0

            results.append(Result(
                name: "removeInsert.cycle", subject: "tower.direct", n: n, opsPerBatch: pairOps,
                perOpNs: sample(opsPerBatch: pairOps) {
                    var acc = 0
                    for i in 0..<pairs {
                        acc &+= m.remove(ring[cursor]) ?? 0
                        ring[cursor] = m.insert(i &+ seed)
                        cursor = (cursor + 1) % ring.count
                    }
                    sink(acc)
                }
            ))

            var cowRing = cowHandles
            var cowCursor = 0

            results.append(Result(
                name: "removeInsert.cycle", subject: "tower.cow", n: n, opsPerBatch: pairOps,
                perOpNs: sample(opsPerBatch: pairOps) {
                    var acc = 0
                    for i in 0..<pairs {
                        acc &+= c.remove(cowRing[cowCursor]) ?? 0
                        cowRing[cowCursor] = c.insert(i &+ seed)
                        cowCursor = (cowCursor + 1) % cowRing.count
                    }
                    sink(acc)
                }
            ))

            results.append(Result(
                name: "removeInsert.cycle", subject: "stdlib.dictionary", n: n, opsPerBatch: pairOps,
                perOpNs: sample(opsPerBatch: pairOps) {
                    var acc = 0
                    var high = n
                    for _ in 0..<pairs {
                        sd[high] = high
                        acc &+= sd.removeValue(forKey: high) ?? 0
                        high &+= 1
                    }
                    sink(acc)
                }
            ))

            results.append(Result(
                name: "iterate.full", subject: "tower.direct", n: n, opsPerBatch: ops,
                perOpNs: sample(opsPerBatch: ops) {
                    var sum = 0
                    for _ in 0..<passes {
                        m.forEach { sum &+= $0 }
                    }
                    sink(sum)
                }
            ))

            // half-holes: 2n slots, odd handles removed → n live
            var holey = MoveMap<Int>(slotCapacity: Index<Int>.Count(UInt(2 * n)))
            var holeyHandles: [Store.Generational.Handle] = []
            holeyHandles.reserveCapacity(2 * n)
            for i in 0..<(2 * n) { holeyHandles.append(holey.insert(i &+ seed)) }
            for (i, h) in holeyHandles.enumerated() where i % 2 == 1 { _ = holey.remove(h) }

            results.append(Result(
                name: "iterate.holes", subject: "tower.direct", n: n, opsPerBatch: ops,
                perOpNs: sample(opsPerBatch: ops) {
                    var sum = 0
                    for _ in 0..<passes {
                        holey.forEach { sum &+= $0 }
                    }
                    sink(sum)
                }
            ))

            let reps = Swift.max(1, structureOpsTarget / n)
            let buildOps = reps * n

            // build at reserved capacity: the substrate's only growth door is
            // the explicit arena `grow(to:)` (measured in the arena bench);
            // `slotCapacity` must be positive by precondition, and the cap
            // alternates n/n+1 to keep the per-rep create loop-variant (the
            // counted-loop trap — W4 report note).
            results.append(Result(
                name: "build.reserved", subject: "tower.direct", n: n, opsPerBatch: buildOps,
                perOpNs: sample(opsPerBatch: buildOps) {
                    var acc = 0
                    for r in 0..<reps {
                        var b = MoveMap<Int>(slotCapacity: Index<Int>.Count(UInt(n &+ (r & 1))))
                        var last = b.insert(seed)
                        for i in 1..<n { last = b.insert(i &+ seed) }
                        acc &+= b.withElement(at: last) { $0 }
                    }
                    sink(acc)
                }
            ))
        }

        return results
    }
}
