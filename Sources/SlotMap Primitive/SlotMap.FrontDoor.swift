public import Memory_Allocator_Primitive
public import Memory_Heap_Primitives
public import Storage_Generational_Primitives
public import Storage_Primitive

public typealias SlotMap<E: ~Copyable> =
    __SlotMap<Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<E>>
