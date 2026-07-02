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

public import Memory_Allocator_Primitive
public import Memory_Heap_Primitives
public import Storage_Generational_Primitives
public import Storage_Primitive

// MARK: - SlotMap<E> — the CANONICAL front door ([DS-028])

/// A slot map over the default column: the growable, heap-allocated, pool-backed
/// generational store.
///
/// This is the canonical front-door alias ([DS-028]) — the sanctioned
/// [API-NAME-004] generic-instantiation exception that pins the default column so
/// consumers spell `SlotMap<Element>`, never the carrier `__SlotMap` or a full
/// column. The alias fully specializes: conformances, the pinned constructors, and
/// `~Copyable` elements all flow through it with zero forwarding and zero runtime
/// cost.
///
/// ```swift
/// var m = SlotMap<Int>(slotCapacity: 4)          // move-only (this alias)
/// var c = SlotMap<Int>.Shared(slotCapacity: 4)    // CoW ownership variant (SlotMap.Shared.swift)
/// ```
///
/// The `Shared` (CoW ownership) variant lives behind a nested alias on the family:
/// `SlotMap<E>.Shared`. `Small`/`Inline` allocation variants and a `.Bounded`
/// capacity variant are consumer-pulled and land as they gain live consumers.
public typealias SlotMap<E: ~Copyable> =
    __SlotMap<Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>>
