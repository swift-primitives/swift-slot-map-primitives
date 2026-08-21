public import Buffer_Protocol_Primitives
public import Index_Primitives
import Ordinal_Primitives_Standard_Library_Integration
public import SlotMap_Primitive
public import Store_Protocol_Primitives

extension __SlotMap
where
    S: ~Copyable,
    S: Store.`Protocol` & Buffer.`Protocol`
{

    @inlinable
    public var count: Index_Primitives.Index<S.Element>.Count {
        store.count
    }

    @inlinable
    public var isEmpty: Bool { store.isEmpty }

    @inlinable
    public var capacity: Index_Primitives.Index<S.Element>.Count { store.capacity }

    @inlinable
    public var freeCapacity: Index_Primitives.Index<S.Element>.Count {
        store.capacity.subtract.saturating(store.count)
    }
}
