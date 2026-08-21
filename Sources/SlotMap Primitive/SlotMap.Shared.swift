public import Buffer_Protocol_Primitives
public import Ownership_Shared_Primitive
public import Store_Protocol_Primitives

extension __SlotMap
where
    S: ~Copyable,
    S: Store.`Protocol` & Buffer.`Protocol`
{

    public typealias Shared = __SlotMap<Ownership.Shared<S.Element, S>>
}
