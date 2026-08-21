import Index_Primitives
public import Memory_Allocator_Primitive
public import Memory_Heap_Primitives
public import Ownership_Shared_Primitive
public import SlotMap_Primitive
public import Storage_Generational_Primitives
public import Storage_Primitive
public import Store_Primitive
public import Store_Protocol_Primitives

extension __SlotMap where S: ~Copyable {

    @inlinable
    @discardableResult
    public mutating func insert<E: ~Copyable>(_ element: consuming E) -> Handle
    where S == Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E> {
        store.insert(element)
    }

    @inlinable
    @discardableResult
    public mutating func insert<E: ~Copyable>(_ element: consuming E) -> Handle
    where S == Ownership.Shared<E, Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>> {
        store.withUnique(consuming: element) { column, element in
            column.insert(element)
        }
    }
}

extension __SlotMap where S: ~Copyable {

    @inlinable
    public mutating func remove<E: ~Copyable>(_ handle: Handle) -> E?
    where S == Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E> {
        store.remove(handle)
    }

    @inlinable
    public mutating func remove<E: ~Copyable>(_ handle: Handle) -> E?
    where S == Ownership.Shared<E, Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>> {
        store.withUnique { $0.remove(handle) }
    }

    @inlinable
    public mutating func removeAll<E: ~Copyable>()
    where S == Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E> {
        store.removeAll()
    }

    @inlinable
    public mutating func removeAll<E: ~Copyable>()
    where S == Ownership.Shared<E, Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>> {
        store.withUnique { $0.removeAll() }
    }
}

extension __SlotMap where S: ~Copyable {

    @inlinable
    public func contains<E: ~Copyable>(_ handle: Handle) -> Bool
    where S == Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E> {
        store.contains(handle)
    }

    @inlinable
    public func contains<E: ~Copyable>(_ handle: Handle) -> Bool
    where S == Ownership.Shared<E, Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>> {
        store.withColumn { $0.contains(handle) }
    }

    @inlinable
    public func withElement<E: ~Copyable, R>(
        at handle: Handle,
        _ body: (borrowing E) -> R
    ) -> R where S == Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E> {
        body(store[handle])
    }

    @inlinable
    public func withElement<E: ~Copyable, R>(
        at handle: Handle,
        _ body: (borrowing E) -> R
    ) -> R
    where S == Ownership.Shared<E, Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>> {
        store.withColumn { body($0[handle]) }
    }

    @inlinable
    public mutating func withMutableElement<E: ~Copyable, R>(
        at handle: Handle,
        _ body: (inout E) -> R
    ) -> R where S == Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E> {
        body(&store[handle])
    }

    @inlinable
    public mutating func withMutableElement<E: ~Copyable, R>(
        at handle: Handle,
        _ body: (inout E) -> R
    ) -> R
    where S == Ownership.Shared<E, Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>> {
        store.withUnique { body(&$0[handle]) }
    }
}

extension __SlotMap where S: ~Copyable {

    @inlinable
    public func forEach<E: ~Copyable>(_ body: (borrowing E) -> Void)
    where S == Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E> {
        store.forEach(body)
    }

    @inlinable
    public func forEach<E: ~Copyable>(_ body: (borrowing E) -> Void)
    where S == Ownership.Shared<E, Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>> {
        store.withColumn { $0.forEach(body) }
    }
}

extension __SlotMap where S: Copyable, S: Store.`Protocol` {

    @inlinable
    public borrowing func clone() -> Self {
        var result = copy self
        result.store.unshare()
        return result
    }
}

extension __SlotMap where S: ~Copyable {

    @inlinable
    public func clone<E>() -> Self
    where S == Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E> {
        Self(store: store.clone())
    }
}
