import Buffer_Primitives_Test_Support
import Index_Primitives
import Memory_Allocator_Primitive
import Memory_Heap_Primitives
import Ownership_Shared_Primitive
import SlotMap_Primitives
import Storage_Generational_Primitives
import Storage_Primitive
import Store_Primitive
import Testing

private typealias Slots<E: ~Copyable> =
    Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>

@Suite
struct `Slot Map Column Law Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}

    @Test
    func `the shared generational column obeys the seam ledger laws`() {
        let violations = Seam.Ledger.violations(
            makeEmpty: { Ownership.Shared(Slots<Int>.create(slotCapacity: 4)) },
            element: { $0 }
        )
        #expect(violations.isEmpty, "\(violations)")
    }
}

@Suite(.serialized)
struct `Slot Map Core Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}

    @Test
    func `insert, contains, withElement, remove, stale handles, counts`() {
        var m = SlotMap<Int>(slotCapacity: 4)
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
        let hasH1 = m.contains(h1)
        let hasH2 = m.contains(h2)
        #expect(!hasH1)
        #expect(hasH2)
    }

    @Test
    func `forEach walks occupied slots; removeAll stales everything`() {
        var m = SlotMap<Int>(slotCapacity: 4)
        let h1 = m.insert(1)
        _ = m.insert(2)
        _ = m.remove(h1)
        _ = m.insert(3)
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
        var m = SlotMap<Int>(slotCapacity: 4)
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

@Suite(.serialized)
struct `Slot Map CoW Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}

    @Test
    func `sibling handles survive a copy-on-write detach — live and stale alike`() {
        var a = SlotMap<Int>.Shared(slotCapacity: 4)
        let hStale = a.insert(1)
        _ = a.remove(hStale)
        let hLive = a.insert(2)
        let b = a
        a.insert(3)
        let aCount = a.count
        let bCount = b.count
        #expect(aCount == Index<Int>.Count(UInt(2)))
        #expect(bCount == Index<Int>.Count(UInt(1)))
        let liveOnBoth = a.contains(hLive) && b.contains(hLive)
        #expect(liveOnBoth)
        let staleOnBoth = a.contains(hStale) || b.contains(hStale)
        #expect(!staleOnBoth)
        let aV = a.withElement(at: hLive) { copy $0 }
        let bV = b.withElement(at: hLive) { copy $0 }
        #expect(aV == 2)
        #expect(bV == 2)
    }

    @Test
    func `mutation through a handle detaches; the sibling keeps the old element`() {
        var a = SlotMap<Int>.Shared(slotCapacity: 2)
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
        #expect(stillOnB)
    }

    @Test
    func `generic clone always detaches; removeAll detaches`() {
        var a = SlotMap<Int>.Shared(slotCapacity: 2)
        let h = a.insert(9)
        var c = a.clone()
        c.withMutableElement(at: h) { $0 = 90 }
        let mine = a.withElement(at: h) { copy $0 }
        #expect(mine == 9)
        let b = a
        a.removeAll()
        let aEmpty = a.isEmpty
        let bHas = b.contains(h)
        #expect(aEmpty)
        #expect(bHas)
    }
}

@Suite(.serialized)
struct `Slot Map Teardown Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}

    @Test
    func `the direct lane tears down live slots via the leaf oracle`() {
        MapProbe.reset()
        do {
            var m = SlotMap<MapItem>(slotCapacity: 4)
            _ = m.insert(MapItem(1))
            let h2 = m.insert(MapItem(2))
            if let removed: MapItem = m.remove(h2) {
                let id = removed.id
                #expect(id == 2)
            } else {
                Issue.record("expected the removed element")
            }
            let mid = MapProbe.sorted
            #expect(mid == [2])
        }
        let all = MapProbe.sorted
        #expect(all == [1, 2])
    }

    @Test
    func `the boxed move-only lane tears down via the box drain`() {
        MapProbe2.reset()
        do {
            var m = SlotMap<MapItem2>.Shared(slotCapacity: 4)
            _ = m.insert(MapItem2(7))
            _ = m.insert(MapItem2(8))
            let n = m.count
            #expect(n == Index<MapItem2>.Count(UInt(2)))
        }
        let all = MapProbe2.sorted
        #expect(all == [7, 8])
    }
}

private struct MapItem: ~Copyable {
    let id: Int
    init(_ id: Int) { self.id = id }
    deinit { MapProbe.record(id) }
}

private enum MapProbe {}

extension MapProbe {

    nonisolated(unsafe) static var _destroyed: [Int] = []
    static func reset() { unsafe _destroyed = [] }
    static func record(_ id: Int) { unsafe _destroyed.append(id) }
    static var sorted: [Int] { unsafe _destroyed.sorted() }
}

private struct MapItem2: ~Copyable {
    let id: Int
    init(_ id: Int) { self.id = id }
    deinit { MapProbe2.record(id) }
}

private enum MapProbe2 {}

extension MapProbe2 {

    nonisolated(unsafe) static var _destroyed: [Int] = []
    static func reset() { unsafe _destroyed = [] }
    static func record(_ id: Int) { unsafe _destroyed.append(id) }
    static var sorted: [Int] { unsafe _destroyed.sorted() }
}

@Suite
struct `Slot Map Sendable Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}

    @Test
    func `sendable composes through both columns`() {
        let a = SlotMap<Int>(slotCapacity: 1)
        requireSendable(a)
        let b = SlotMap<Int>.Shared(slotCapacity: 1)
        requireSendable(b)
        #expect(Bool(true))
    }
}

private func requireSendable<T: Sendable & ~Copyable>(_ value: borrowing T) {}
