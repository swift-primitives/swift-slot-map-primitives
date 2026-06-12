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

// The W2 slot-map model suite (arc-2): the ADT's public surface rides the same
// seeded streams as the ledger underneath — handle laws (generation continuity,
// α/β), typed counts, removeAll, forEach order — on BOTH columns. The Shared
// lane runs a sibling FLEET: forks copy the reference model with the value, so
// every sibling audits against its own fork after every op; a copy-on-write
// leak (a mutation bleeding across siblings) or a handle staled by a detach
// fails that sibling's audit immediately. Teardown exactness via the census on
// the move-only direct lane.
//
// Determinism: generation reads MODEL state only; pool hand-outs are
// single-threaded deterministic. Shape constraint (arc-2 incident 2.5): each op
// is its own small method on a ~Copyable stream struct.

import SlotMap_Primitives
import Storage_Primitive
import Storage_Generational_Primitives
import Store_Primitive
import Buffer_Primitives_Test_Support
import Memory_Heap_Primitives
import Memory_Allocator_Primitive
import Shared_Primitive
import Index_Primitives
import Testing

private typealias Slots<E: ~Copyable> =
    Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>
private typealias MoveMap<E: ~Copyable> = SlotMap<Slots<E>>
private typealias CoWMap<E: ~Copyable> = SlotMap<Shared<E, Slots<E>>>

private typealias Handle = Store.Generational.Handle

// MARK: - The reference model (the ledger as plain value state; forked by copy)

private struct Reference {
    struct Slot {
        var occupied = false
        var generation = 0
        var id: Int? = nil
    }

    var slots: [Slot]
    var live: [(handle: Handle, id: Int)] = []
    var stale: [(handle: Handle, id: Int)] = []

    init(capacity: Int) {
        self.slots = Swift.Array(repeating: Slot(), count: capacity)
    }

    var capacity: Int { slots.count }
    var liveCount: Int { live.count }

    /// Occupied slots ascending — the `forEach` contract's expected id sequence.
    var idsInSlotOrder: [Int] {
        slots.compactMap { $0.occupied ? $0.id : nil }
    }

    mutating func admit(_ handle: Handle, id: Int) -> [String] {
        var findings: [String] = []
        guard handle.index >= 0, handle.index < slots.count else {
            return ["minted handle index \(handle.index) outside capacity \(slots.count)"]
        }
        if slots[handle.index].occupied {
            findings.append("minted handle for slot \(handle.index), which the ledger holds OCCUPIED")
        }
        if slots[handle.index].generation != handle.generation {
            findings.append(
                "generation continuity broken at slot \(handle.index): minted \(handle.generation), ledger \(slots[handle.index].generation)"
            )
        }
        slots[handle.index].occupied = true
        slots[handle.index].id = id
        live.append((handle, id))
        return findings
    }

    mutating func retire(liveAt position: Int) {
        let entry = live.remove(at: position)
        slots[entry.handle.index].occupied = false
        slots[entry.handle.index].generation += 1
        slots[entry.handle.index].id = nil
        addStale(entry)
    }

    mutating func retireAll() {
        for entry in live {
            slots[entry.handle.index].occupied = false
            slots[entry.handle.index].generation += 1
            slots[entry.handle.index].id = nil
            addStale(entry)
        }
        live.removeAll()
    }

    private mutating func addStale(_ entry: (handle: Handle, id: Int)) {
        stale.append(entry)
        if stale.count > 16 {
            stale.removeFirst(stale.count - 16)
        }
    }
}

// MARK: - The direct move-only lane (handle laws + teardown exactness; the
// census + the tracked element are the hoisted Model fixtures — W3-0)

private struct DirectStream: ~Copyable {
    var map: MoveMap<Model.Element.Tracked>
    var model: Reference
    var rng: Model.Random
    var verdict: Model.Verdict
    var nextID = 0
    var expectedDeaths = 0
    let census: Model.Census

    init(seed: UInt64, census: Model.Census) {
        var rng = Model.Random(seed: seed)
        let capacity = 2 + rng.below(11)
        self.map = MoveMap<Model.Element.Tracked>(slotCapacity: Index<Model.Element.Tracked>.Count(UInt(capacity)))
        self.model = Reference(capacity: capacity)
        self.rng = rng
        self.verdict = Model.Verdict(seed: seed)
        self.census = census
    }

    mutating func insertNew() {
        let id = nextID
        nextID += 1
        let handle = map.insert(Model.Element.Tracked(id: id, census: census))
        verdict.record("insert id=\(id) → @\(handle.index)g\(handle.generation)")
        verdict.diverged(model.admit(handle, id: id))
    }

    mutating func removeLive() {
        let position = rng.below(model.live.count)
        let entry = model.live[position]
        verdict.record("remove id=\(entry.id)")
        if let element: Model.Element.Tracked = map.remove(entry.handle) {
            if element.id != entry.id {
                verdict.diverged(["remove returned id \(element.id), model \(entry.id)"])
            }
            model.retire(liveAt: position)
            expectedDeaths += 1
        } else {
            verdict.diverged(["remove rejected a LIVE handle (α)"])
        }
    }

    mutating func removeStale() {
        let entry = model.stale[rng.below(model.stale.count)]
        verdict.record("stale-remove @\(entry.handle.index)g\(entry.handle.generation)")
        if let element: Model.Element.Tracked = map.remove(entry.handle) {
            verdict.diverged(["STALE handle re-validated through remove (β): id \(element.id)"])
        }
    }

    mutating func readLive() {
        let entry = model.live[rng.below(model.live.count)]
        verdict.record("read id=\(entry.id)")
        let id = map.withElement(at: entry.handle) { (element: borrowing Model.Element.Tracked) in element.id }
        if id != entry.id {
            verdict.diverged(["withElement at live handle: \(id), model \(entry.id)"])
        }
    }

    mutating func mutateLive() {
        let position = rng.below(model.live.count)
        let entry = model.live[position]
        let id = nextID
        nextID += 1
        verdict.record("mutate @\(entry.handle.index) \(entry.id)→\(id)")
        let census = self.census
        map.withMutableElement(at: entry.handle) { (element: inout Model.Element.Tracked) in
            element = Model.Element.Tracked(id: id, census: census)
        }
        expectedDeaths += 1  // the displaced element
        model.live[position].id = id
        model.slots[entry.handle.index].id = id
        if !map.contains(entry.handle) {
            verdict.diverged(["mutation through a handle staled it"])
        }
    }

    mutating func containsLive() {
        let entry = model.live[rng.below(model.live.count)]
        verdict.record("has id=\(entry.id)")
        if !map.contains(entry.handle) {
            verdict.diverged(["live handle rejected by contains (α)"])
        }
    }

    mutating func containsStale() {
        let entry = model.stale[rng.below(model.stale.count)]
        verdict.record("stale-has @\(entry.handle.index)g\(entry.handle.generation)")
        if map.contains(entry.handle) {
            verdict.diverged(["stale handle accepted by contains (β)"])
        }
    }

    mutating func forEachCheck() {
        verdict.record("walk \(model.liveCount)")
        var seen: [Int] = []
        map.forEach { (element: borrowing Model.Element.Tracked) in seen.append(element.id) }
        let expected = model.idsInSlotOrder
        if seen != expected {
            verdict.diverged(["forEach walked \(seen), model slot order \(expected)"])
        }
    }

    mutating func wipe() {
        verdict.record("wipe \(model.liveCount) live")
        expectedDeaths += model.liveCount
        map.removeAll()
        model.retireAll()
    }

    func audit() -> [String] {
        var findings: [String] = []
        if map.count != Index<Model.Element.Tracked>.Count(UInt(model.liveCount)) {
            findings.append("count: map \(map.count), model \(model.liveCount)")
        }
        if map.capacity != Index<Model.Element.Tracked>.Count(UInt(model.capacity)) {
            findings.append("capacity: map \(map.capacity), model \(model.capacity)")
        }
        if map.freeCapacity != Index<Model.Element.Tracked>.Count(UInt(model.capacity - model.liveCount)) {
            findings.append("freeCapacity: map \(map.freeCapacity), model \(model.capacity - model.liveCount)")
        }
        for entry in model.live {
            if !map.contains(entry.handle) {
                findings.append("α: live handle @\(entry.handle.index)g\(entry.handle.generation) rejected")
            } else {
                let id = map.withElement(at: entry.handle) { (element: borrowing Model.Element.Tracked) in element.id }
                if id != entry.id {
                    findings.append("live handle resolves \(id), model \(entry.id)")
                }
            }
        }
        for entry in model.stale where map.contains(entry.handle) {
            findings.append("β: stale handle @\(entry.handle.index)g\(entry.handle.generation) re-validated")
        }
        if census.died.count != expectedDeaths {
            findings.append("teardown drift: \(census.died.count) deaths, expected \(expectedDeaths)")
        }
        return findings
    }

    mutating func step() {
        var branch = rng.below(100)
        // Redirect order: stale-ops → reads; empty → insert; full-insert → remove LAST.
        if model.stale.isEmpty, branch >= 50, branch < 56 { branch = 62 }
        if model.stale.isEmpty, branch >= 80, branch < 86 { branch = 62 }
        if model.live.isEmpty, branch >= 28, branch < 92 { branch = 0 }
        if model.liveCount == model.capacity, branch < 28 { branch = 30 }

        switch branch {
        case 0..<28: insertNew()
        case 28..<50: removeLive()
        case 50..<56: removeStale()
        case 56..<72: readLive()
        case 72..<80: mutateLive()
        case 80..<86: containsStale()
        case 86..<92: containsLive()
        case 92..<98: forEachCheck()
        default: wipe()
        }
    }

    mutating func run() {
        let operations = Model.operations(default: 800)
        var op = 0
        while op < operations, verdict.isClean {
            step()
            if Model.shouldAudit(op: op, of: operations) {
                verdict.diverged(audit())
            }
            op += 1
        }
    }

    consuming func finish() -> (verdict: Model.Verdict, expectedDeaths: Int, liveAtEnd: Int) {
        (verdict, expectedDeaths, model.liveCount)
    }
}

private func runDirectStream(seed: UInt64) -> Model.Verdict {
    let census = Model.Census()
    var stream = DirectStream(seed: seed, census: census)
    stream.run()
    let (finished, expectedDeaths, liveAtEnd) = stream.finish()  // the map dies here
    var verdict = finished

    if census.died.count != expectedDeaths + liveAtEnd {
        verdict.findings.append(
            "teardown inexact at end: \(census.died.count) deaths, expected \(expectedDeaths) + \(liveAtEnd) live"
        )
    }
    if census.born.sorted() != census.died.sorted() {
        verdict.findings.append(
            "teardown multiset broken: \(census.born.count) born vs \(census.died.count) died"
        )
    }
    return verdict
}

// MARK: - The direct trivial lane (+ the clone fork — clone forks the model too)

private struct CloneStream: ~Copyable {
    var map: MoveMap<Int>
    var model: Reference
    var rng: Model.Random
    var verdict: Model.Verdict
    var nextID = 0

    init(seed: UInt64) {
        var rng = Model.Random(seed: seed)
        let capacity = 2 + rng.below(11)
        self.map = MoveMap<Int>(slotCapacity: Index<Int>.Count(UInt(capacity)))
        self.model = Reference(capacity: capacity)
        self.rng = rng
        self.verdict = Model.Verdict(seed: seed)
    }

    mutating func insertNew() {
        let id = nextID
        nextID += 1
        let handle = map.insert(id)
        verdict.record("insert id=\(id) → @\(handle.index)g\(handle.generation)")
        verdict.diverged(model.admit(handle, id: id))
    }

    mutating func removeLive() {
        let position = rng.below(model.live.count)
        let entry = model.live[position]
        verdict.record("remove id=\(entry.id)")
        if let element: Int = map.remove(entry.handle) {
            if element != entry.id {
                verdict.diverged(["remove returned id \(element), model \(entry.id)"])
            }
            model.retire(liveAt: position)
        } else {
            verdict.diverged(["remove rejected a LIVE handle (α)"])
        }
    }

    mutating func readLive() {
        let entry = model.live[rng.below(model.live.count)]
        verdict.record("read id=\(entry.id)")
        let id = map.withElement(at: entry.handle) { (element: borrowing Int) in copy element }
        if id != entry.id {
            verdict.diverged(["withElement at live handle: \(id), model \(entry.id)"])
        }
    }

    /// The clone fork: the copy gets its own forked model; both run a few ops
    /// independently; both audits must hold (handles live on both, divergence none).
    mutating func cloneFork() {
        verdict.record("clone-fork")
        var copy = map.clone()
        var forked = model  // the model forks WITH the value

        for entry in forked.live {
            if !copy.contains(entry.handle) {
                verdict.diverged(["clone dropped live handle @\(entry.handle.index)g\(entry.handle.generation)"])
            }
        }
        for entry in forked.stale where copy.contains(entry.handle) {
            verdict.diverged(["clone re-validated a stale handle @\(entry.handle.index)"])
        }

        // Diverge the copy: one insert (if space) + one removal (if live).
        if forked.liveCount < forked.capacity {
            let id = nextID
            nextID += 1
            let handle = copy.insert(id)
            verdict.diverged(forked.admit(handle, id: id))
        }
        if !forked.live.isEmpty {
            let position = rng.below(forked.live.count)
            let entry = forked.live[position]
            if let element: Int = copy.remove(entry.handle) {
                if element != entry.id {
                    verdict.diverged(["forked remove returned \(element), model \(entry.id)"])
                }
                forked.retire(liveAt: position)
            } else {
                verdict.diverged(["forked remove rejected a live handle"])
            }
        }

        // The fork holds on the copy…
        if copy.count != Index<Int>.Count(UInt(forked.liveCount)) {
            verdict.diverged(["forked count: copy \(copy.count), forked model \(forked.liveCount)"])
        }
        // …and the ORIGINAL is untouched by the copy's divergence (the next
        // regular audit re-proves it in full; count is the cheap immediate check).
        if map.count != Index<Int>.Count(UInt(model.liveCount)) {
            verdict.diverged(["clone divergence leaked into the original's count"])
        }
    }

    mutating func wipe() {
        verdict.record("wipe \(model.liveCount) live")
        map.removeAll()
        model.retireAll()
    }

    func audit() -> [String] {
        var findings: [String] = []
        if map.count != Index<Int>.Count(UInt(model.liveCount)) {
            findings.append("count: map \(map.count), model \(model.liveCount)")
        }
        for entry in model.live {
            if !map.contains(entry.handle) {
                findings.append("α: live handle @\(entry.handle.index)g\(entry.handle.generation) rejected")
            } else {
                let id = map.withElement(at: entry.handle) { (element: borrowing Int) in copy element }
                if id != entry.id {
                    findings.append("live handle resolves \(id), model \(entry.id)")
                }
            }
        }
        for entry in model.stale where map.contains(entry.handle) {
            findings.append("β: stale handle @\(entry.handle.index) re-validated")
        }
        return findings
    }

    mutating func step() {
        var branch = rng.below(100)
        if model.live.isEmpty, branch >= 30, branch < 86 { branch = 0 }
        if model.liveCount == model.capacity, branch < 30 { branch = 34 }

        switch branch {
        case 0..<30: insertNew()
        case 30..<56: removeLive()
        case 56..<78: readLive()
        case 78..<86: cloneFork()
        case 86..<94: cloneFork()
        default: wipe()
        }
    }

    mutating func run() {
        let operations = Model.operations(default: 600)
        var op = 0
        while op < operations, verdict.isClean {
            step()
            if Model.shouldAudit(op: op, of: operations) {
                verdict.diverged(audit())
            }
            op += 1
        }
    }

    consuming func finish() -> Model.Verdict {
        verdict
    }
}

private func runCloneStream(seed: UInt64) -> Model.Verdict {
    var stream = CloneStream(seed: seed)
    stream.run()
    return stream.finish()
}

// MARK: - The Shared (CoW) lane: the sibling fleet, each against its own fork

private struct FleetStream {
    var siblings: [CoWMap<Int>]
    var models: [Reference]
    var rng: Model.Random
    var verdict: Model.Verdict
    var nextID = 0

    init(seed: UInt64) {
        var rng = Model.Random(seed: seed)
        let capacity = 4 + rng.below(9)
        self.siblings = [CoWMap<Int>(slotCapacity: Index<Int>.Count(UInt(capacity)))]
        self.models = [Reference(capacity: capacity)]
        self.rng = rng
        self.verdict = Model.Verdict(seed: seed)
    }

    mutating func fork() {
        let source = rng.below(siblings.count)
        verdict.record("fork ←\(source) (\(siblings.count + 1) siblings)")
        siblings.append(siblings[source])  // the CoW moment: a plain value copy
        models.append(models[source])      // the model forks with it
    }

    mutating func drop() {
        let target = rng.below(siblings.count)
        verdict.record("drop \(target) (\(siblings.count - 1) siblings)")
        siblings.remove(at: target)
        models.remove(at: target)
    }

    mutating func insertNew(into target: Int) {
        let id = nextID
        nextID += 1
        let handle = siblings[target].insert(id)
        verdict.record("insert[\(target)] id=\(id) → @\(handle.index)g\(handle.generation)")
        verdict.diverged(models[target].admit(handle, id: id))
    }

    mutating func removeLive(from target: Int) {
        let position = rng.below(models[target].live.count)
        let entry = models[target].live[position]
        verdict.record("remove[\(target)] id=\(entry.id)")
        if let element: Int = siblings[target].remove(entry.handle) {
            if element != entry.id {
                verdict.diverged(["remove returned id \(element), model \(entry.id)"])
            }
            models[target].retire(liveAt: position)
        } else {
            verdict.diverged(["remove rejected a LIVE handle (α) on sibling \(target)"])
        }
    }

    mutating func mutateLive(on target: Int) {
        let position = rng.below(models[target].live.count)
        let entry = models[target].live[position]
        let id = nextID
        nextID += 1
        verdict.record("mutate[\(target)] @\(entry.handle.index) \(entry.id)→\(id)")
        siblings[target].withMutableElement(at: entry.handle) { (element: inout Int) in
            element = id
        }
        models[target].live[position].id = id
        models[target].slots[entry.handle.index].id = id
    }

    mutating func readLive(on target: Int) {
        let entry = models[target].live[rng.below(models[target].live.count)]
        verdict.record("read[\(target)] id=\(entry.id)")
        let id = siblings[target].withElement(at: entry.handle) { (element: borrowing Int) in copy element }
        if id != entry.id {
            verdict.diverged(["withElement on sibling \(target): \(id), model \(entry.id)"])
        }
    }

    mutating func containsStale(on target: Int) {
        let entry = models[target].stale[rng.below(models[target].stale.count)]
        verdict.record("stale-has[\(target)] @\(entry.handle.index)g\(entry.handle.generation)")
        if siblings[target].contains(entry.handle) {
            verdict.diverged(["stale handle accepted on sibling \(target) (β)"])
        }
    }

    mutating func wipe(_ target: Int) {
        verdict.record("wipe[\(target)] \(models[target].liveCount) live")
        siblings[target].removeAll()
        models[target].retireAll()
    }

    mutating func forEachCheck(on target: Int) {
        verdict.record("walk[\(target)] \(models[target].liveCount)")
        var seen: [Int] = []
        siblings[target].forEach { (element: borrowing Int) in seen.append(copy element) }
        let expected = models[target].idsInSlotOrder
        if seen != expected {
            verdict.diverged(["forEach on sibling \(target) walked \(seen), model \(expected)"])
        }
    }

    /// Every sibling against its OWN fork — the cross-sibling leak detector.
    func audit() -> [String] {
        var findings: [String] = []
        for (index, model) in models.enumerated() {
            if siblings[index].count != Index<Int>.Count(UInt(model.liveCount)) {
                findings.append("sibling \(index) count \(siblings[index].count), model \(model.liveCount)")
            }
            for entry in model.live {
                if !siblings[index].contains(entry.handle) {
                    findings.append("α: sibling \(index) rejected live @\(entry.handle.index)g\(entry.handle.generation)")
                } else {
                    let id = siblings[index].withElement(at: entry.handle) { (element: borrowing Int) in copy element }
                    if id != entry.id {
                        findings.append("sibling \(index) resolves \(id) at @\(entry.handle.index), model \(entry.id)")
                    }
                }
            }
            for entry in model.stale where siblings[index].contains(entry.handle) {
                findings.append("β: sibling \(index) re-validated stale @\(entry.handle.index)g\(entry.handle.generation)")
            }
        }
        return findings
    }

    mutating func step() {
        let target = rng.below(siblings.count)
        var branch = rng.below(100)
        if model(target, isEmpty: true), branch >= 16, branch < 84 { branch = 10 }
        if model(target, isFull: true), branch >= 10, branch < 16 { branch = 34 }
        if models[target].stale.isEmpty, branch >= 78, branch < 84 { branch = 64 }

        switch branch {
        case 0..<10 where siblings.count < 4: fork()
        case 0..<10: readOrInsert(target)
        case 10..<16: insertNew(into: target)
        case 16..<34 where siblings.count > 1: drop()
        case 16..<34: readOrInsert(target)
        case 34..<52: removeLive(from: target)
        case 52..<64: mutateLive(on: target)
        case 64..<78: readLive(on: target)
        case 78..<84: containsStale(on: target)
        case 84..<90: forEachCheck(on: target)
        case 90..<96: readOrInsert(target)
        default: wipe(target)
        }
    }

    private func model(_ target: Int, isEmpty: Bool = false, isFull: Bool = false) -> Bool {
        if isEmpty { return models[target].live.isEmpty }
        if isFull { return models[target].liveCount == models[target].capacity }
        return false
    }

    private mutating func readOrInsert(_ target: Int) {
        if models[target].live.isEmpty {
            if models[target].liveCount < models[target].capacity {
                insertNew(into: target)
            } else {
                forEachCheck(on: target)
            }
        } else {
            readLive(on: target)
        }
    }

    mutating func run() {
        let operations = Model.operations(default: 800)
        var op = 0
        while op < operations, verdict.isClean {
            step()
            if Model.shouldAudit(op: op, of: operations) {
                verdict.diverged(audit())
            }
            op += 1
        }
    }
}

private func runFleetStream(seed: UInt64) -> Model.Verdict {
    var stream = FleetStream(seed: seed)
    stream.run()
    return stream.verdict
}

// MARK: - The suites

@Suite
struct `SlotMap Model` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
}

extension `SlotMap Model`.Integration {
    @Test(arguments: Model.seeds(default: [0x51A7_3A21, 0x0D1C_E5E5]))
    func `direct move-only stream: handle laws hold and teardown is exact`(seed: UInt64) {
        let verdict = runDirectStream(seed: seed)
        #expect(verdict.isClean, Comment(rawValue: verdict.report))
    }

    @Test(arguments: Model.seeds(default: [0xC107_E5E5, 0xF02C_ED01]))
    func `direct trivial stream with clone forks: both forks track their models`(seed: UInt64) {
        let verdict = runCloneStream(seed: seed)
        #expect(verdict.isClean, Comment(rawValue: verdict.report))
    }

    @Test(arguments: Model.seeds(default: [0x5A42_ED01, 0xB0C5_0101, 0xF1EE_7777]))
    func `shared sibling fleet: every sibling tracks its own fork through detaches`(seed: UInt64) {
        let verdict = runFleetStream(seed: seed)
        #expect(verdict.isClean, Comment(rawValue: verdict.report))
    }
}

extension `SlotMap Model`.Unit {
    @Test
    func `typed counts cohere: count + freeCapacity == capacity throughout`() {
        var map = MoveMap<Int>(slotCapacity: 4)
        let h1 = map.insert(1)
        _ = map.insert(2)
        let count = map.count
        let free = map.freeCapacity
        #expect(count == Index<Int>.Count(2))
        #expect(free == Index<Int>.Count(2))
        _ = map.remove(h1)
        let countAfter = map.count
        let freeAfter = map.freeCapacity
        #expect(countAfter == Index<Int>.Count(1))
        #expect(freeAfter == Index<Int>.Count(3))
    }
}

extension `SlotMap Model`.`Edge Case` {
    @Test
    func `a sibling forked while a handle was stale keeps rejecting it after detach`() {
        var first = CoWMap<Int>(slotCapacity: 2)
        let handle = first.insert(7)
        let removed: Int? = first.remove(handle)
        #expect(removed == 7)

        var second = first  // fork at stale-handle state
        _ = second.insert(9)  // detach

        let staleOnFirst = first.contains(handle)
        let staleOnSecond = second.contains(handle)
        #expect(!staleOnFirst)
        #expect(!staleOnSecond)
        let ghostFirst: Int? = first.remove(handle)
        let ghostSecond: Int? = second.remove(handle)
        #expect(ghostFirst == nil)
        #expect(ghostSecond == nil)
    }

    @Test
    func `removeAll on one sibling leaves the other's elements and handles intact`() {
        var first = CoWMap<Int>(slotCapacity: 3)
        let a = first.insert(1)
        let b = first.insert(2)
        var second = first

        second.removeAll()

        let secondEmpty = second.isEmpty
        #expect(secondEmpty)
        let aOnFirst = first.contains(a)
        let bOnFirst = first.contains(b)
        #expect(aOnFirst)
        #expect(bOnFirst)
        let one = first.withElement(at: a) { (element: borrowing Int) in copy element }
        let two = first.withElement(at: b) { (element: borrowing Int) in copy element }
        #expect(one == 1)
        #expect(two == 2)
        let aOnSecond = second.contains(a)
        #expect(!aOnSecond)
    }
}
