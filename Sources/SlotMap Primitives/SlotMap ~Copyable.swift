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

public import Buffer_Protocol_Primitives
public import Index_Primitives
import Ordinal_Primitives_Standard_Library_Integration
// The GENERIC slot-map surface: the count vocabulary rides the observability seam
// ([DS-025]: `where S: Store.`Protocol` & Buffer.`Protocol`` on the capability
// extension, restored here now that the carrier itself is bound-free); the
// HANDLE ops pin per column (`SlotMap+Columns.swift`) — handles are not seam
// vocabulary, by design (the W2c/W3b deferrals' point, kept).
public import SlotMap_Primitive
public import Store_Protocol_Primitives

extension __SlotMap
where
    S: ~Copyable,
    S: Store.`Protocol` & Buffer.`Protocol`
{
    /// The number of live (occupied) slots.
    @inlinable
    public var count: Index_Primitives.Index<S.Element>.Count {
        store.count
    }

    /// Whether no slots are occupied.
    @inlinable
    public var isEmpty: Bool { store.isEmpty }

    /// The total slot capacity.
    @inlinable
    public var capacity: Index_Primitives.Index<S.Element>.Count { store.capacity }

    /// The number of free slots.
    ///
    /// - Complexity: O(1)
    @inlinable
    public var freeCapacity: Index_Primitives.Index<S.Element>.Count {
        store.capacity.subtract.saturating(store.count)
    }
}
