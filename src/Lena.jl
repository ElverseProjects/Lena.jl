module Lena

export @python, @c, @rust, AbstractProvider

"""
    AbstractProvider

Base type for Lena provider objects.

Current MVP providers:
- `Lena.PythonProvider` from `@python`
- `Lena.C.CProvider` from `@c` or `Lena.C.load(path)`
"""
abstract type AbstractProvider end

include("PythonProvider.jl")
include("CProvider.jl")
include("RustProvider.jl")

"""
    @python code_string

Create an inline Python provider using PythonCall.jl.

Example:

```julia
py = @python "def add(a, b):\n    return a + b\n"
py.add(1, 2)
```
"""
macro python(code)
    if !(code isa String)
        throw(ArgumentError("@python expects a string literal, preferably a triple-quoted string"))
    end
    return :(Lena.PythonProvider($code))
end

"""
    @c code_string

Create an inline C provider.

The C code is written into Lena's build cache, compiled into a shared library,
loaded with `Libdl`, and wrapped as a provider object.

Functions intended to be visible to Lena should be marked with `LENA_EXPORT`.
"""
macro c(code)
    if !(code isa String)
        throw(ArgumentError("@c expects a string literal, preferably a triple-quoted string"))
    end
    return :(Lena.C.inline($code))
end

"""
    @rust code_string

Create an inline Rust provider.

Functions intended to be visible to Lena should be marked with `@export`.
Lena turns them into `#[no_mangle] pub extern "C" fn ...`, builds a Rust
`cdylib` with Cargo, and calls it through the same C ABI layer as `@c`.
"""
macro rust(code)
    if !(code isa String)
        throw(ArgumentError("@rust expects a string literal, preferably a triple-quoted string"))
    end
    return :(Lena.Rust.inline($code))
end

end # module Lena
