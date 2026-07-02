// exports.swift
// SlotMap Primitive declares the hoisted carrier `struct __SlotMap<S: ~Copyable>`
// ([DS-025]) + take() + the pinned column constructors, plus the front doors
// ([DS-028]): the canonical `SlotMap<E>` alias and the `SlotMap<E>.Shared`
// ownership variant. Per the exports-narrowing ruling (audit #9, 2026-06-10),
// nothing is re-exported: consumers SPELL their column by importing the
// column-vocabulary modules explicitly (Storage/Memory/Shared/Store/Index).
