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
public import Shared_Primitive
public import Store_Protocol_Primitives

// MARK: - SlotMap<E>.Shared — the OWNERSHIP variant ([DS-028])

extension __SlotMap
where
    S: ~Copyable,
    S: Store.`Protocol` & Buffer.`Protocol`
{

    /// The explicit CoW (value-semantic) slot map: the current column boxed behind
    /// `Shared`.
    ///
    /// This is an ownership-axis variant alias ([DS-028]) — a column-preserving
    /// transformer that wraps the member it is named on (`Shared` wraps `S`
    /// unconditionally, so it chains correctly ahead of any future allocation or
    /// capacity variant): outstanding handles survive copy-on-write detaches,
    /// because the column's clone strategy preserves slot indices, occupancy, and
    /// generations exactly.
    ///
    /// A live consumer of this package's own test suite pulls the direct spelling
    /// (`Shared<E, Slots<E>>`) throughout the CoW lane — this alias is the
    /// front-door respelling of that spelling.
    public typealias Shared = __SlotMap<Shared_Primitive.Shared<S.Element, S>>
}
