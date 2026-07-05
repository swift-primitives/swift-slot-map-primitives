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

import Index_Primitives
public import Memory_Allocator_Primitive
public import Memory_Heap_Primitives
public import Shared_Primitive
// The COLUMN-PINNED handle surface. Handles cannot ride the positional seam (that is
// the design: identity is `(index, generation)`, validated), so every op pins per
// ratified column; the `Shared` forms cross the box via the gate-first scoped
// accessors ([MEM-OWN-017]: inserted elements thread as consuming closure PARAMETERS).
public import SlotMap_Primitive
public import Storage_Generational_Primitives
public import Storage_Primitive
public import Store_Primitive
public import Store_Protocol_Primitives

// ============================================================================
// MARK: - Insert (mints a handle; the pool owns placement)
// ============================================================================

extension __SlotMap where S: ~Copyable {
    /// Inserts an element; returns a fresh handle to its slot (direct column).
    ///
    /// - Precondition: the slot map is not full.
    /// - Complexity: O(1)
    @inlinable
    @discardableResult
    public mutating func insert<E: ~Copyable>(_ element: consuming E) -> Handle
    where S == Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E> {
        store.insert(element)
    }

    /// Inserts an element (`Shared` column; uniqueness restored first — siblings keep
    /// their elements AND their handles, which remain valid on both boxes).
    ///
    /// - Precondition: the slot map is not full.
    /// - Complexity: O(1) (O(`capacity`) when a copy must be made first)
    @inlinable
    @discardableResult
    public mutating func insert<E: ~Copyable>(_ element: consuming E) -> Handle
    where S == Shared_Primitive.Shared<E, Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>> {
        store.withUnique(consuming: element) { column, element in
            column.insert(element)
        }
    }
}

// ============================================================================
// MARK: - Remove (stales outstanding handles to the slot)
// ============================================================================

extension __SlotMap where S: ~Copyable {
    /// Removes by handle; returns the element if the handle was live, nil if stale.
    ///
    /// - Complexity: O(1)
    @inlinable
    public mutating func remove<E: ~Copyable>(_ handle: Handle) -> E?
    where S == Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E> {
        store.remove(handle)
    }

    /// Removes by handle (`Shared` column; uniqueness restored first).
    ///
    /// - Complexity: O(1) (O(`capacity`) when a copy must be made first)
    @inlinable
    public mutating func remove<E: ~Copyable>(_ handle: Handle) -> E?
    where S == Shared_Primitive.Shared<E, Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>> {
        store.withUnique { $0.remove(handle) }
    }

    /// Removes every element, staling all outstanding handles (direct column).
    @inlinable
    public mutating func removeAll<E: ~Copyable>()
    where S == Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E> {
        store.removeAll()
    }

    /// Removes every element (`Shared` column; detaches first — siblings keep theirs).
    @inlinable
    public mutating func removeAll<E: ~Copyable>()
    where S == Shared_Primitive.Shared<E, Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>> {
        store.withUnique { $0.removeAll() }
    }
}

// ============================================================================
// MARK: - Validated access
// ============================================================================

extension __SlotMap where S: ~Copyable {
    /// Whether the handle is live (in range, occupied, generation matches).
    @inlinable
    public func contains<E: ~Copyable>(_ handle: Handle) -> Bool
    where S == Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E> {
        store.contains(handle)
    }

    /// Whether the handle is live (`Shared` column; no gate — reads never detach).
    @inlinable
    public func contains<E: ~Copyable>(_ handle: Handle) -> Bool
    where S == Shared_Primitive.Shared<E, Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>> {
        store.withColumn { $0.contains(handle) }
    }

    /// Borrowing access to the element at a live handle (direct column).
    ///
    /// - Precondition: the handle is live (use `contains` for a soft check).
    @inlinable
    public func withElement<E: ~Copyable, R>(
        at handle: Handle,
        _ body: (borrowing E) -> R
    ) -> R where S == Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E> {
        body(store[handle])
    }

    /// Borrowing access (`Shared` column; no gate).
    ///
    /// - Precondition: the handle is live.
    @inlinable
    public func withElement<E: ~Copyable, R>(
        at handle: Handle,
        _ body: (borrowing E) -> R
    ) -> R where S == Shared_Primitive.Shared<E, Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>> {
        store.withColumn { body($0[handle]) }
    }

    /// Mutating access to the element at a live handle (direct column).
    ///
    /// - Precondition: the handle is live.
    @inlinable
    public mutating func withMutableElement<E: ~Copyable, R>(
        at handle: Handle,
        _ body: (inout E) -> R
    ) -> R where S == Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E> {
        body(&store[handle])
    }

    /// Mutating access (`Shared` column; uniqueness restored FIRST — the sibling keeps
    /// the unmutated element, and its handle stays valid there).
    ///
    /// - Precondition: the handle is live.
    @inlinable
    public mutating func withMutableElement<E: ~Copyable, R>(
        at handle: Handle,
        _ body: (inout E) -> R
    ) -> R where S == Shared_Primitive.Shared<E, Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>> {
        store.withUnique { body(&$0[handle]) }
    }
}

// ============================================================================
// MARK: - Iteration (occupied slots, slot order)
// ============================================================================

// swift-format-ignore: AmbiguousTrailingClosureOverload
// Column-pinned overload pair: the `where` clauses bind S to distinct concrete
// columns, so exactly one overload is viable per instantiation (no real ambiguity).
extension __SlotMap where S: ~Copyable {
    /// Calls the closure for each live element, in slot order (direct column).
    ///
    /// - Complexity: O(`capacity`)
    @inlinable
    public func forEach<E: ~Copyable>(_ body: (borrowing E) -> Void)
    where S == Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E> {
        store.forEach(body)
    }

    /// Calls the closure for each live element (`Shared` column; no gate).
    ///
    /// - Complexity: O(`capacity`)
    @inlinable
    public func forEach<E: ~Copyable>(_ body: (borrowing E) -> Void)
    where S == Shared_Primitive.Shared<E, Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>> {
        store.withColumn { $0.forEach(body) }
    }
}

// ============================================================================
// MARK: - Cloning (generic on the CoW column; direct column pinned)
// ============================================================================

extension __SlotMap where S: Copyable, S: Store.`Protocol` {
    /// Returns an independent copy — outstanding handles remain valid on BOTH values
    /// (the generation-preserving clone).
    ///
    /// - Complexity: O(`capacity`)
    @inlinable
    public borrowing func clone() -> Self {
        var result = copy self
        result.store.unshare()
        return result
    }
}

extension __SlotMap where S: ~Copyable {
    /// Returns an independent copy with the same handles live (direct column).
    ///
    /// - Complexity: O(`capacity`)
    @inlinable
    public func clone<E>() -> Self
    where S == Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E> {
        Self(store: store.clone())
    }
}
