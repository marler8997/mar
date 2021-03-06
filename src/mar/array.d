module mar.array;

// Sometimes allows static array literals with -betterC
// I've seen it work when the ElementType is a primitive type
// rather than a struct.
template StaticArray(ElementType, T...)
{
    static ElementType[T.length] StaticArray = [T];
}
template StaticImmutableArray(ElementType, T...)
{
    static immutable ElementType[T.length] StaticImmutableArray = [T];
}

auto fixedArrayBuilder(T, size_t size)()
{
    // Meant to make arrays when they can't be made with array literals because of -betterC bugs.
    struct Builder
    {
        private size_t next;
        private T[size] array = void;
        auto ref put(T element)
        {
            if (next < size)
                array[next] = element;
            next++;
            return this;
        }
        auto finish(string filename = __FILE__, uint line = __LINE__)
        {
            if (next != size)
            {
                import mar.stdio;
                import mar.process : exit;
                stderr.writeln(filename, "(", line, "): change size of fixedArrayBuilder from ", size, " to ", next);
                exit(1);
            }
            return array;
        }
    }
    return Builder(0);
}

template isArrayLike(T)
{
    enum isArrayLike =
           is(typeof(T.init.length))
        && is(typeof(T.init.ptr))
        && is(typeof(T.init[0]));
}
template isPointerLike(T)
{
    enum isPointerLike =
           T.sizeof == (void*).sizeof
        && is(typeof(T.init[0]));
}

template isIndexable(T)
{
    enum isIndexable = is(typeof(T.init[0]));
}

auto asDynamic(T, size_t size)(ref T[size] array)
{
    pragma(inline, true);
    T[] dynamicArray = array;
    return dynamicArray;
}

struct MallocArrayPointerResult(T)
{
    T* val;
    alias val this;
    final bool failed() const { return val is null; }
}
MallocArrayPointerResult!T tryMallocArrayGetPointer(T)(size_t length)
{
    pragma(inline, true);
    import mar.mem : malloc;

    return MallocArrayPointerResult!T(cast(T*)malloc(T.sizeof * length));
}

struct MallocArrayResult(T)
{
    T[] val;
    alias val this;
    final bool failed() const { return val.ptr == null; }
}
MallocArrayResult!T tryMallocArray(T)(size_t length)
{
    pragma(inline, true);
    auto result = tryMallocArrayGetPointer!T(length);
    if (result.failed)
        return MallocArrayResult!T(null);
    else
        return MallocArrayResult!T(result.val[0 .. length]);
}

bool contains(T, U)(T arr, U elem)
{
    pragma(inline, true);
    return indexOf!(T,U)(arr, elem) != arr.length;
}
auto indexOrLength(T, U)(T arr, U elem)
{
    foreach(i; 0 .. arr.length)
    {
        if (arr[i] is elem)
            return i;
    }
    return arr.length;
}
auto lastIndexOrLength(T, U)(T arr, U elem)
{
    foreach_reverse(i; 0 .. arr.length)
    {
        if (arr[i] is elem)
            return i;
    }
    return arr.length;
}

auto indexOrMax(T, U)(T arr, U elem)
{
    size_t i = 0;
    foreach(ref e; arr)
    {
        if (e is elem)
            return i;
        i++;
    }
    return typeof(return).max;
}
auto lastIndexOrMax(T, U)(T arr, U elem)
{
    size_t i = arr.length;
    foreach_reverse(ref e; arr)
    {
        i--;
        if (e is elem)
            return i;
    }
    return typeof(return).max;
}

auto find(T, U)(inout(T)* ptr, const(T)* limit, U elem)
{
    for (;ptr < limit; ptr++)
    {
        if (ptr[0] is elem)
            break;
    }
    return ptr;
}

// The size of each array element.  If the actual size is 0, then it
// is assumed to be 1.
template ElementSizeForCopy(alias Array)
{
    static if (Array[0].sizeof == 0)
        enum ElementSizeForCopy = 1;
    else
        enum ElementSizeForCopy = Array[0].sizeof;
}

/**
acopy - Array Copy
*/
void acopy(T,U)(T dst, U src) @trusted
if (isArrayLike!T && isArrayLike!U && dst[0].sizeof == src[0].sizeof && dst[0].alignof == src[0].alignof)
in { assert(dst.length >= src.length, "copyFrom source length larger than destination"); } do
{
    pragma(inline, true);
    static assert (!__traits(isStaticArray, T), "acopy doest not accept static arrays since they are passed by value");
    import mar.mem : MaxAlignType, alignedMemcpy;
    alias E = MaxAlignType!(typeof(dst[0]));
    alignedMemcpy(cast(E*)dst.ptr, cast(const(E)*)src.ptr, src.length * dst[0].sizeof);
}
/// ditto
void acopy(T,U)(T dst, U src) @system
if (isArrayLike!T && isPointerLike!U && dst[0].sizeof == src[0].sizeof && dst[0].alignof == src[0].alignof)
{
    pragma(inline, true);
    static assert (!__traits(isStaticArray, T), "acopy doest not accept static arrays since they are passed by value");
    import mar.mem : MaxAlignType, alignedMemcpy;
    alias E = MaxAlignType!(typeof(dst[0]));
    alignedMemcpy(cast(E*)dst.ptr, cast(const(E)*)src, dst.length * dst[0].sizeof);
}
/// ditto
void acopy(T,U)(T dst, U src) @system
if (isPointerLike!T && isArrayLike!U && dst[0].sizeof == src[0].sizeof && dst[0].alignof == src[0].alignof)
{
    pragma(inline, true);
    import mar.mem : MaxAlignType, alignedMemcpy;
    alias E = MaxAlignType!(typeof(dst[0]));
    alignedMemcpy(cast(E*)dst, cast(const(E)*)src.ptr, src.length * dst[0].sizeof);
}
/// ditto
void acopy(T,U)(T dst, U src, size_t size) @system
if (isPointerLike!T && isPointerLike!U && dst[0].sizeof == src[0].sizeof && dst[0].alignof == src[0].alignof)
{
    pragma(inline, true);
    import mar.mem : MaxAlignType, alignedMemcpy;
    alias E = MaxAlignType!(typeof(dst[0]));
    alignedMemcpy(cast(E*)dst, cast(const(E)*)src, size * dst[0].sizeof);
}

/**
amove - Array move, dst and src can overlay
*/
void amove(T,U)(T dst, U src) @trusted
if (isArrayLike!T && isArrayLike!U && dst[0].sizeof == src[0].sizeof)
in { assert(dst.length >= src.length, "moveFrom source length larger than destination"); } do
{
    pragma(inline, true);
    static assert (!__traits(isStaticArray, T), "amove doest not accept static arrays since they are passed by value");
    import mar.mem : memmove;
    memmove(cast(void*)dst.ptr, cast(void*)src.ptr, src.length * ElementSizeForCopy!dst);
}
/// ditto
void amove(T,U)(T dst, U src) @system
if (isArrayLike!T && isPointerLike!U && dst[0].sizeof == src[0].sizeof)
{
    pragma(inline, true);
    static assert (!__traits(isStaticArray, T), "amove doest not accept static arrays since they are passed by value");
    import mar.mem : memmove;
    memmove(cast(void*)dst.ptr, cast(void*)src, dst.length * ElementSizeForCopy!dst);
}
/// ditto
void amove(T,U)(T dst, U src) @system
if (isPointerLike!T && isArrayLike!U && dst[0].sizeof == src[0].sizeof)
{
    pragma(inline, true);
    import mar.mem : memmove;
    memmove(cast(void*)dst, cast(void*)src.ptr, src.length * ElementSizeForCopy!dst);
}
/// ditto
void amove(T,U)(T dst, U src, size_t size) @system
if (isPointerLike!T && isPointerLike!U && dst[0].sizeof == src[0].sizeof)
{
    pragma(inline, true);
    import mar.mem : memmove;
    memmove(cast(void*)dst, cast(void*)src, size * ElementSizeForCopy!dst);
}

private size_t diffIndex(const(void)* lhs, const(void)* rhs, size_t limit)
{
    /*
    TODO: implement the faster version here
    size_t next = size_t.sizeof;
    for (;;)
    {
        if (next <= limit)
        {
            if
        }
        dstPtr[0] = srcPtr[0];
    }
    ubyte* dstPtr2 = cast(ubyte*)dstPtr;
    ubyte* srcPtr2 = cast(ubyte*)srcPtr;
    for ( ;length > 0; dstPtr2++, srcPtr2++, length--)
    {
        dstPtr2[0] = srcPtr2[0];
    }
    */
    for (size_t i = 0; ; i++)
    {
        if (i >= limit || (cast(ubyte*)lhs)[i] != (cast(ubyte*)rhs)[i])
            return i;
    }
    return 0;
}


// TODO: need to handle SentinelPtr and SentinelArray
//       correctly where it matches the array but is not ended
bool aequals(T,U)(T lhs, U rhs)
if (isIndexable!T && isIndexable!U)
{
    pragma(inline, true);
    static if (isArrayLike!T)
    {
        static if (isArrayLike!U)
        {
            if (lhs.length != rhs.length)
                return false;
            auto length = lhs[0].sizeof * lhs.length;
            return length == diffIndex(cast(void*)lhs.ptr,
                cast(void*)rhs.ptr, length);
        }
        else
        {
            auto length = lhs[0].sizeof * lhs.length;
            return length == diffIndex(cast(void*)lhs.ptr,
                cast(void*)rhs, length);
        }
    }
    else static if (isArrayLike!U)
    {
        auto length = rhs[0].sizeof * rhs.length;
        return length == diffIndex(cast(void*)rhs.ptr,
            cast(void*)lhs, length);
    }
    else static assert(0, "invalid types for aequals");
}
private bool aequals(const(void)* lhs, const(void)* rhs, size_t length)
{
    return length == diffIndex(lhs, rhs, length);
}

bool startsWith(T,U)(T lhs, U rhs)
if (isArrayLike!T)
{
    if (lhs.length < rhs.length)
        return false;
    return aequals(&lhs[0], &rhs[0], rhs.length);
}
bool startsWith(T,U)(T lhs, U rhs)
if (isPointerLike!T)
{
    return aequals(lhs, &rhs[0], rhs.length);
}
bool endsWith(T,U)(T lhs, U rhs)
//if (isArrayLike!T && isArrayLike!U)
{
    if (lhs.length < rhs.length)
        return false;
    return aequals(&lhs[lhs.length - rhs.length], &rhs[0], rhs.length);
}

void zero(T)(T[] array)
{
    static import mar.mem;
    mar.mem.zero(array.ptr, array.length * T.sizeof);
}

void setBytes(T,U)(T dst, U value)
if (isArrayLike!T && T.init[0].sizeof == 1 && value.sizeof == 1)
{
    pragma(inline, true);
    version (NoStdc)
    {
        static assert(0, "not impl");
    }
    else
    {
        import core.stdc.string : memset;
        memset(dst.ptr, cast(int)value, dst.length);
    }
}

// A fixed size static array, that allows you to add/remove items
struct StaticArray(T, size_t Capacity)
{
    import mar.expect : MemoryResult;

    private T[Capacity] buffer;
    private size_t _length;

    auto ref opIndex(size_t index) inout { return buffer[index]; }
    T[] data() const { pragma(inline, true); return (cast(T[])buffer)[0 .. _length]; }
    auto length() const { return _length; }
    auto capacity() const { return Capacity; }

    MemoryResult tryPut(T item)
    {
        if (_length == buffer.length)
            return MemoryResult.outOfMemory;

        buffer[_length++] = item;
        return MemoryResult.success;
    }
    MemoryResult tryPutRange(U)(U[] items)
    {
        import mar.array : acopy;

        auto lengthNeeded = _length + items.length;
        if (lengthNeeded > buffer.length)
            return MemoryResult.outOfMemory;

        acopy(buffer.ptr + _length, items);
        _length += items.length;
        return MemoryResult.success;
    }
    void removeAt(size_t index)
    {
        for (size_t i = index; i + 1 < _length; i++)
        {
            buffer[i] = buffer[i+1];
        }
        _length--;
    }

    auto pop()
    {
        auto result = buffer[_length-1];
        _length--;
        return result;
    }
}



/**
TODO: move this to the mored repository

A LimitArray is like an array, except it contains 2 pointers, "ptr" and "limit",
instead of a "ptr" and "length".

The first pointer, "ptr", points to the beginning (like a normal array) and the
second pointer, "limit", points to 1 element past the last element in the array.

```
-------------------------------
| first | second | ... | last |
-------------------------------
 ^                             ^
 ptr                           limit
````

To get the length of the LimitArray, you can evaluate `limit - ptr`.
To check if a LimitArray is empty, you can check if `ptr == limit`.

The reason for the existense of the LimitArray structure is that some functionality
is more efficient when it uses this representation.  A common example is when processing
or parsing an array of elements where the beginning is iteratively "sliced off" as
it is being processed, i.e.  array = array[someCount .. $];  This operation is more efficient
when using a LimitArray because only the "ptr" field needs to be modified whereas a normal array
needs to modify the "ptr" field and the "length" each time. Note that other operations are more
efficiently done using a normal array, for example, if the length needs to be evaluated quite
often then it might make more sense to use a normal array.

In order to support "Element Type Modifiers" on a LimitArray's pointer types, the types are
defined using a template. Here is a table of LimitArray types with their equivalent normal array types.

| Normal Array        | Limit Array             |
|---------------------|-------------------------|
| `char[]`            | `LimitArray!char.mutable` `LimitArray!(const(char)).mutable` `LimitArray!(immutable(char)).mutable` |
| `const(char)[]`     | `LimitArray!char.const` `LimitArray!(const(char)).const` `LimitArray!(immutable(char)).const` |
| `immutable(char)[]` | `LimitArray!char.immutable` `LimitArray!(const(char)).immutable` `LimitArray!(immutable(char)).immutable` |

*/
template LimitArray(T)
{
    static if( !is(T == Unqual!T) )
    {
        alias LimitArray = LimitArray!(Unqual!T);
    }
    else
    {
        enum CommonMixin = q{
            @property auto asArray()
            {
                pragma(inline, true);
                return this.ptr[0 .. limit - ptr];
            }
            auto slice(size_t offset)
            {
                pragma(inline, true);
                auto newPtr = ptr + offset;
                assert(newPtr <= limit, "slice offset range violation");
                return typeof(this)(newPtr, limit);
            }
            auto slice(size_t offset, size_t newLimit)
                in { assert(newLimit >= offset, "slice offset range violation"); } do
            {
                pragma(inline, true);
                auto newLimitPtr = ptr + newLimit;
                assert(newLimitPtr <= limit, "slice limit range violation");
                return typeof(this)(ptr + offset, ptr + newLimit);
            }
            auto ptrSlice(typeof(this.ptr) ptr)
            {
                pragma(inline, true);
                auto copy = this;
                copy.ptr = ptr;
                return copy;
            }
        };

        struct mutable
        {
            union
            {
                struct
                {
                    T* ptr;
                    T* limit;
                }
                const_ constVersion;
            }
            // mutable is implicitly convertible to const
            alias constVersion this;

            mixin(CommonMixin);
        }
        struct immutable_
        {
            union
            {
                struct
                {
                    immutable(T)* ptr;
                    immutable(T)* limit;
                }
                const_ constVersion;
            }
            // immutable is implicitly convertible to const
            alias constVersion this;

            mixin(CommonMixin);
        }
        struct const_
        {
            const(T)* ptr;
            const(T)* limit;
            mixin(CommonMixin);
            auto startsWith(const(T)[] check) const
            {
                return ptr + check.length <= limit &&
                    0 == memcmp(ptr, check.ptr, check.length);
            }
            auto equals(const(T)[] check) const
            {
                return ptr + check.length == limit &&
                    0 == memcmp(ptr, check.ptr, check.length);
            }
        }
    }
}

@property auto asLimitArray(T)(T[] array)
{
    pragma(inline, true);
    static if( is(T == immutable) )
    {
        return LimitArray!T.immutable_(array.ptr, array.ptr + array.length);
    }
    else static if( is(T == const) )
    {
        return LimitArray!T.const_(array.ptr, array.ptr + array.length);
    }
    else
    {
        return LimitArray!T.mutable(array.ptr, array.ptr + array.length);
    }
}

/**
TODO: move this to the mored repo

An array type that uses a custom type for the length.
*/
struct LengthArray(T, SizeType)
{
    @property static typeof(this) nullValue() { return typeof(this)(null, 0); }

    T* ptr;
    SizeType length;

    void nullify() { this.ptr = null; this.length = 0; }
    bool isNull() const { return ptr is null; }

    @property auto ref last() const
        in { assert(length > 0); } do { pragma(inline, true); return ptr[length - 1]; }

    auto ref opIndex(SizeType index) inout
        in { assert(index < length, format("range violation %s >= %s", index, length)); } do
    {
        pragma(inline, true);
        return ptr[index];
    }
    static if (size_t.sizeof != SizeType.sizeof)
    {
        auto ref opIndex(size_t index) inout
            in { assert(index < length, format("range violation %s >= %s", index, length)); } do
        {
            pragma(inline, true);
            return ptr[index];
        }
    }
    SizeType opDollar() const
    {
        pragma(inline, true);
        return length;
    }
    /*
    auto ref opSlice(SizeType start, SizeType limit) inout
        in { assert(limit >= start, "slice range violation"); } do
    {
        pragma(inline, true);
        return inout LengthArray!(T,SizeType)(ptr + start, cast(SizeType)(limit - start));
    }
    */
    auto ref opSlice(SizeType start, SizeType limit)
        in { assert(limit >= start, "slice range violation"); } do
    {
        pragma(inline, true);
        return LengthArray!(T,SizeType)(ptr + start, cast(SizeType)(limit - start));
    }

    int opApply(scope int delegate(ref T element) dg) const
    {
        pragma(inline, true);
        int result = 0;
        for (SizeType i = 0; i < length; i++)
        {
            result = dg(*cast(T*)&ptr[i]);
            if (result)
                break;
        }
        return result;
    }
    int opApply(scope int delegate(SizeType index, ref T element) dg) const
    {
        pragma(inline, true);
        int result = 0;
        for (SizeType i = 0; i < length; i++)
        {
            result = dg(i, *cast(T*)&ptr[i]);
            if (result)
                break;
        }
        return result;
    }

    @property auto asArray() { return ptr[0..length]; }
    //alias toArray this;

    /*
    // range functions
    @property bool empty() { return length == 0; }
    @property auto front() { return *ptr; }
    void popFront() {
        ptr++;
        length--;
    }
    */
}
LengthArray!(T, LengthType) asLengthArray(LengthType, T)(T[] array)
in {
    static if (LengthType.sizeof < array.length.sizeof)
    {
        assert(array.length <= LengthType.max,
            format("array length %s exceeded " ~ LengthType.stringof ~ ".max %s", array.length, LengthType.max));
    }
} do
{
    pragma(inline, true);
    return LengthArray!(T, LengthType)(array.ptr, cast(LengthType)array.length);
}

LengthArray!(T, LengthType) asLengthArray(LengthType, T)(T* ptr, LengthType length)
{
    pragma(inline, true);
    return LengthArray!(T, LengthType)(ptr, length);
}


void areverse(T)(T* start, T* limit)
{
    for (;;)
    {
        limit--;
        if (limit <= start)
            break;
        const temp = start[0];
        start[0] = limit[0];
        limit[0] = temp;
        start++;
    }
}