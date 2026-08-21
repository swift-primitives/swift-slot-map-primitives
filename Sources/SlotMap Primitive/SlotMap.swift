public import Index_Primitives
public import Memory_Allocator_Primitive
public import Memory_Heap_Primitives
public import Ownership_Shared_Primitive
public import Storage_Generational_Primitives
public import Storage_Primitive
public import Store_Primitive

@_documentation(visibility: public)
@frozen
public struct __SlotMap<S: ~Copyable>: ~Copyable {

    @usableFromInline
    package var store: S

    @inlinable
    public init(store: consuming S) {
        self.store = store
    }
}

extension __SlotMap where S: ~Copyable {

    @inlinable
    public consuming func take() -> S {
        store
    }
}

extension __SlotMap: Copyable where S: Copyable {}

extension __SlotMap: Sendable where S: Sendable & ~Copyable {}

extension __SlotMap where S: ~Copyable {

    public typealias Handle = Store.Generational.Handle
}

extension __SlotMap where S: ~Copyable {

    @inlinable
    public init<E: ~Copyable>(slotCapacity: Index<E>.Count)
    where S == Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E> {
        self.init(store: S.create(slotCapacity: slotCapacity))
    }

    @inlinable
    public init<E>(slotCapacity: Index<E>.Count)
    where S == Ownership.Shared<E, Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>> {
        self.init(
            store: Ownership.Shared(
                Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>.create(
                    slotCapacity: slotCapacity
                )
            )
        )
    }

    @inlinable
    public init<E: ~Copyable>(slotCapacity: Index<E>.Count)
    where S == Ownership.Shared<E, Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>> {
        self.init(
            store: Ownership.Shared(
                Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>.create(
                    slotCapacity: slotCapacity
                )
            )
        )
    }
}
