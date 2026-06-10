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

// The column-keyed slot-map suite: the generational column direct + Shared-wrapped.

private typealias Slots<E: ~Copyable> =
    Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>

private typealias MoveMap<E: ~Copyable> = SlotMap<Slots<E>>
private typealias CoWMap<E: ~Copyable> = SlotMap<Shared<E, Slots<E>>>

// ⚠️ DEBUG CARVE-OUT (2026-06-10, ADT-families leg 7): every functional suite below is
// compiled out of DEBUG test runs and verified in RELEASE ONLY. A 6.3.2 DEBUG-mode
// codegen bug (§A9 family; EXC_BAD_ACCESS at 0x10 in compiler-synthesized accessors,
// ASLR-sensitive) crashes ANY generic-extension member of a generic ~Copyable wrapper
// struct whose field is `Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>` —
// same-module or cross-module, @frozen or not, @inlinable or not, witness or concrete
// pin, Tagged or Bool returns (all bisected). The identical wrapper shape over the
// ring/linear columns is green everywhere, and bare generic FUNCTIONS over the
// generational column are green (the arena suite's [DS-024] law run). Release builds
// pass all suites deterministically. Minimal repro preserved at
// .handoffs/probes-2026-06-10/slotmap-debug-crash/; root-cause arc = a queued
// /issue-investigation (candidate fix: the column's internal representation).
// Precedent: the set-ordered §A9 guards.
#if !DEBUG

// MARK: - [DS-024]: the Shared-wrapped generational column is lawful (the direct
// column's law-run lives in the arena suite; this is the family's NEW composite)

@Suite
struct SlotMapColumnLawTests {

    @Test(.disabled("""
        6.3.2 §A9-family RELEASE crash: the seam witnesses THROUGH Shared over the
        generational column (generic law fn → Shared witness → Generational member)
        EXC_BAD_ACCESS — the only release-crashing path, and also the only path the
        SlotMap surface never uses (handle ops + withUnique). [DS-024] verification
        carve-out, pending the queued /issue-investigation; every other column's laws
        are verified (arena: direct generational; shared/queue/array: Shared over
        linear + both rings).
        """))
    func `the shared generational column obeys the seam ledger laws`() {
        let violations = Seam.Ledger.violations(
            makeEmpty: { Shared(Slots<Int>.create(slotCapacity: 4)) },
            element: { $0 }
        )
        #expect(violations.isEmpty, "\(violations)")
    }
}

// MARK: - The direct (move-only) lane

@Suite(.serialized)
struct SlotMapCoreTests {

    @Test
    func `insert, contains, withElement, remove, stale handles, counts`() {
        var m = MoveMap<Int>(slotCapacity: 4)
        let isEmpty = m.isEmpty
        #expect(isEmpty)
        let h1 = m.insert(10)
        let h2 = m.insert(20)
        let n = m.count
        #expect(n == Index<Int>.Count(UInt(2)))
        let free = m.freeCapacity
        #expect(free == Index<Int>.Count(UInt(2)))
        let v = m.withElement(at: h2) { copy $0 }
        #expect(v == 20)
        m.withMutableElement(at: h1) { $0 += 1 }
        let v1 = m.withElement(at: h1) { copy $0 }
        #expect(v1 == 11)
        let removed: Int? = m.remove(h1)
        #expect(removed == 11)
        let stale: Int? = m.remove(h1)
        #expect(stale == nil)
        let hasH1 = m.contains(h1), hasH2 = m.contains(h2)
        #expect(!hasH1)
        #expect(hasH2)
    }

    @Test
    func `forEach walks occupied slots; removeAll stales everything`() {
        var m = MoveMap<Int>(slotCapacity: 4)
        let h1 = m.insert(1)
        _ = m.insert(2)
        _ = m.remove(h1)
        _ = m.insert(3)                         // reuses slot 0 (fresh generation)
        var seen: [Int] = []
        m.forEach { seen.append($0) }
        #expect(seen.sorted() == [2, 3])
        m.removeAll()
        let isEmpty = m.isEmpty
        #expect(isEmpty)
        var seen2: [Int] = []
        m.forEach { seen2.append($0) }
        #expect(seen2.isEmpty)
    }

    @Test
    func `pinned clone keeps handles live on both values`() {
        var m = MoveMap<Int>(slotCapacity: 4)
        let h = m.insert(7)
        var c = m.clone()
        let onBoth = m.contains(h) && c.contains(h)
        #expect(onBoth)
        c.withMutableElement(at: h) { $0 = 70 }
        let mine = m.withElement(at: h) { copy $0 }
        let theirs = c.withElement(at: h) { copy $0 }
        #expect(mine == 7)
        #expect(theirs == 70)
    }
}

// MARK: - The CoW lane (the generation-preserving clone through the box)

@Suite(.serialized)
struct SlotMapCoWTests {

    @Test
    func `sibling handles survive a copy-on-write detach — live and stale alike`() {
        var a = CoWMap<Int>(slotCapacity: 4)
        let hStale = a.insert(1)
        _ = a.remove(hStale)                    // stale before the copy
        let hLive = a.insert(2)
        let b = a                               // S5: SlotMap is Copyable because S is
        a.insert(3)                             // withUnique detaches a; b untouched
        let aCount = a.count, bCount = b.count
        #expect(aCount == Index<Int>.Count(UInt(2)))
        #expect(bCount == Index<Int>.Count(UInt(1)))
        let liveOnBoth = a.contains(hLive) && b.contains(hLive)
        #expect(liveOnBoth)                     // THE generation-preserving guarantee
        let staleOnBoth = a.contains(hStale) || b.contains(hStale)
        #expect(!staleOnBoth)
        let aV = a.withElement(at: hLive) { copy $0 }
        let bV = b.withElement(at: hLive) { copy $0 }
        #expect(aV == 2)
        #expect(bV == 2)
    }

    @Test
    func `mutation through a handle detaches; the sibling keeps the old element`() {
        var a = CoWMap<Int>(slotCapacity: 2)
        let h = a.insert(5)
        let b = a
        a.withMutableElement(at: h) { $0 = 50 }
        let mine = a.withElement(at: h) { copy $0 }
        let theirs = b.withElement(at: h) { copy $0 }
        #expect(mine == 50)
        #expect(theirs == 5)
        let removedFromA: Int? = a.remove(h)
        #expect(removedFromA == 50)
        let stillOnB = b.contains(h)
        #expect(stillOnB)                       // b's box untouched by a's removal
    }

    @Test
    func `generic clone always detaches; removeAll detaches`() {
        var a = CoWMap<Int>(slotCapacity: 2)
        let h = a.insert(9)
        var c = a.clone()
        c.withMutableElement(at: h) { $0 = 90 }
        let mine = a.withElement(at: h) { copy $0 }
        #expect(mine == 9)
        let b = a
        a.removeAll()
        let aEmpty = a.isEmpty, bHas = b.contains(h)
        #expect(aEmpty)
        #expect(bHas)
    }
}

// MARK: - Teardown (the leaf oracle + the box drain; release leg = the -O regime)

@Suite(.serialized)
struct SlotMapTeardownTests {

    @Test
    func `the direct lane tears down live slots via the leaf oracle`() {
        MapProbe.reset()
        do {
            var m = MoveMap<MapItem>(slotCapacity: 4)
            _ = m.insert(MapItem(1))
            let h2 = m.insert(MapItem(2))
            if let removed: MapItem = m.remove(h2) {
                let id = removed.id
                #expect(id == 2)
            } else {
                Issue.record("expected the removed element")
            }
            let mid = MapProbe.destroyedSorted
            #expect(mid == [2])
        }
        let all = MapProbe.destroyedSorted
        #expect(all == [1, 2])
    }

    @Test
    func `the boxed move-only lane tears down via the box drain`() {
        MapProbe2.reset()
        do {
            var m = SlotMap<Shared<MapItem2, Slots<MapItem2>>>(slotCapacity: 4)
            _ = m.insert(MapItem2(7))
            _ = m.insert(MapItem2(8))
            let n = m.count
            #expect(n == Index<MapItem2>.Count(UInt(2)))
        }
        let all = MapProbe2.destroyedSorted
        #expect(all == [7, 8])
    }
}

private struct MapItem: ~Copyable {
    let id: Int
    init(_ id: Int) { self.id = id }
    deinit { MapProbe.recordDestroy(id) }
}

private enum MapProbe {
    nonisolated(unsafe) static var _destroyed: [Int] = []
    static func reset() { unsafe _destroyed = [] }
    static func recordDestroy(_ id: Int) { unsafe _destroyed.append(id) }
    static var destroyedSorted: [Int] { unsafe _destroyed.sorted() }
}

private struct MapItem2: ~Copyable {
    let id: Int
    init(_ id: Int) { self.id = id }
    deinit { MapProbe2.recordDestroy(id) }
}

private enum MapProbe2 {
    nonisolated(unsafe) static var _destroyed: [Int] = []
    static func reset() { unsafe _destroyed = [] }
    static func recordDestroy(_ id: Int) { unsafe _destroyed.append(id) }
    static var destroyedSorted: [Int] { unsafe _destroyed.sorted() }
}

#endif

// MARK: - Sendable smoke

@Suite
struct SlotMapSendableTests {

    @Test
    func `sendable composes through both columns`() {
        let a = MoveMap<Int>(slotCapacity: 1)
        requireSendable(a)
        let b = CoWMap<Int>(slotCapacity: 1)
        requireSendable(b)
        #expect(Bool(true))
    }
}

private func requireSendable<T: Sendable & ~Copyable>(_ value: borrowing T) {}

