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

public import Storage_Primitive
public import Storage_Generational_Primitives
public import Store_Primitive
public import Memory_Heap_Primitives
public import Memory_Allocator_Primitive
public import Shared_Primitive
public import Index_Primitives

// MARK: - __SlotMap (the ADT tier — generic over the GENERATIONAL column)

/// A slot map — the handle-keyed sparse ADT over an explicit GENERATIONAL storage
/// COLUMN (the ratified name and home, ADT-families tranche 2026-06-10).
///
/// `__SlotMap` is template-true (the same bound as `__Array`/`__Queue`), and
/// **copyability flows from the column** (S5):
///
/// ```swift
/// __SlotMap<            Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<FD >>   // zero-cost MOVE-ONLY (default)
/// __SlotMap<Shared<Int, Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<Int>>>  // explicit CoW value semantics
/// ```
///
/// HANDLES, not positions, are the slot map's identity: `insert` mints a
/// `(index, generation)` `Store.Generational.Handle`; `remove` bumps the slot's
/// generation so outstanding handles to it go stale; access validates. The column's
/// thin positional seam exists for the generic machinery (the gate, the [DS-024]
/// laws, the `Shared` box) — the pool owns placement, so positional `initialize` is
/// lawful only at the next-free slot. On the CoW column, the GENERATION-PRESERVING
/// clone means sibling values' outstanding handles survive a copy-on-write detach.
///
/// Element-keyed `Equatable`/`Hashable` carriers are deliberately NOT exposed for
/// slot-map columns: `Shared`'s carrier walk reads the prefix `[0, count)` (the
/// linear-family contract), which is unlawful over holey occupancy. A handle-set-keyed
/// equality is its own future design.
///
/// ## Carrier (hoisted per [API-IMPL-009]/[PKG-NAME-006])
///
/// `__SlotMap` is the bound-free carrier ([DS-025]): its column parameter `S` is
/// bound `~Copyable` **only**; every capability (observability, the handle-keyed
/// seam ops, construction) attaches by conditional `@inlinable` extension keyed on
/// the seams the column conforms. The PUBLIC spelling of the family is the
/// front-door aliases — `SlotMap<E>` (canonical) and `SlotMap<E>.Shared` (CoW
/// ownership) — declared in `SlotMap.FrontDoor.swift` / `SlotMap.Shared.swift`
/// ([DS-028]); the hoisted name never appears in consumer signatures.
@_documentation(visibility: public)
@frozen
public struct __SlotMap<S: ~Copyable>: ~Copyable {

    /// The generational storage column — move-only (the default ownership column) or
    /// a `Shared` CoW column. The ADT is a thin handle discipline over it; it carries
    /// NO deinit (teardown lives in the leaf's oracle / the shared box's drain).
    @usableFromInline
    package var store: S

    /// Wraps an existing column.
    @inlinable
    public init(store: consuming S) {
        self.store = store
    }

    /// Consumes the slot map, yielding its storage column.
    @inlinable
    public consuming func take() -> S {
        store
    }
}

// MARK: - Conditional Conformances (co-located per [COPY-FIX-004])

/// The S5 chain: `__SlotMap<Shared<E, B>>` is `Copyable` exactly when the ELEMENT is.
extension __SlotMap: Copyable where S: Copyable {}

extension __SlotMap: Sendable where S: Sendable & ~Copyable {}

// MARK: - The handle vocabulary

extension __SlotMap where S: ~Copyable {
    /// The generational slot handle — the non-generic carrier, storable by any composer.
    public typealias Handle = Store.Generational.Handle
}

// MARK: - Column-pinned construction ([MEM-COPY-017]: the split lives in `Shared`'s
// pinned constructor pairs; the `SlotMap` forms pick the column)

extension __SlotMap where S: ~Copyable {
    /// Creates an empty MOVE-ONLY slot map (the default ownership column).
    /// Typed count per the conversions discipline (Round M A3).
    @inlinable
    public init<E: ~Copyable>(slotCapacity: Index<E>.Count)
    where S == Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E> {
        self.init(store: S.create(slotCapacity: slotCapacity))
    }

    /// Creates an empty CoW (value-semantic) slot map on the `Shared` column.
    ///
    /// Outstanding handles survive copy-on-write detaches: the column's clone strategy
    /// preserves slot indices, occupancy, and generations exactly.
    @inlinable
    public init<E>(slotCapacity: Index<E>.Count)
    where S == Shared_Primitive.Shared<E, Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>> {
        self.init(store: Shared_Primitive.Shared(
            Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>.create(slotCapacity: slotCapacity)
        ))
    }

    /// Creates an empty statically-unique slot map of move-only elements on the
    /// `Shared` column (the boxed flavor of the move-only regime).
    @inlinable
    public init<E: ~Copyable>(slotCapacity: Index<E>.Count)
    where S == Shared_Primitive.Shared<E, Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>> {
        self.init(store: Shared_Primitive.Shared(
            Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>.create(slotCapacity: slotCapacity)
        ))
    }
}
