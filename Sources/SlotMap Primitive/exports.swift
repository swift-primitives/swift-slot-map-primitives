// exports.swift
// SlotMap Primitive declares `struct SlotMap<S>` (the handle-keyed sparse ADT over the
// generational COLUMN) + take() + the pinned column constructors. Per the
// exports-narrowing ruling (audit #9, 2026-06-10), nothing is re-exported: consumers
// SPELL their column by importing the column-vocabulary modules explicitly
// (Storage/Memory/Shared/Store/Index).
