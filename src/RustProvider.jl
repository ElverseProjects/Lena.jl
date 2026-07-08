module Rust

using Libdl
using SHA
import ..AbstractProvider
import ..C

export RustProvider, RustSignature, inline, parse_signatures

"""
    RustSignature

A parsed exported Rust function signature from Lena's `@export fn ...` syntax.

MVP rule: only C-ABI-safe primitive signatures are supported.
"""
struct RustSignature
    name::Symbol
    return_type::Any
    arg_types::Tuple
    arg_names::Vector{String}
    source::String
end

"""
    RustProvider

Provider returned by `@rust` / `Lena.Rust.inline`.

Internally this wraps a `Lena.C.CProvider`, because Rust is compiled to a
`cdylib` and called from Julia through the C ABI.
"""
struct RustProvider <: AbstractProvider
    inner::C.CProvider
    signatures::Dict{Symbol, RustSignature}
    build_dir::String
    crate_name::String
end

function Base.getproperty(provider::RustProvider, name::Symbol)
    if name in (:inner, :signatures, :build_dir, :crate_name)
        return getfield(provider, name)
    end

    inner = getfield(provider, :inner)
    if name in propertynames(inner; private=true)
        return getproperty(inner, name)
    end

    return getproperty(inner, name)
end

function Base.propertynames(provider::RustProvider; private::Bool=false)
    exported = propertynames(getfield(provider, :inner); private=false)
    base = (:inner, :signatures, :build_dir, :crate_name)
    return private ? (base..., exported...) : exported
end

function Base.show(io::IO, provider::RustProvider)
    print(io, "Lena.Rust.RustProvider(", length(provider.signatures), " function")
    length(provider.signatures) == 1 || print(io, "s")
    print(io, ", crate=", provider.crate_name, ")")
end

const RUST_TYPE_MAP = Dict{String, Any}(
    "()" => Cvoid,
    "void" => Cvoid,
    "i8" => Int8,
    "i16" => Int16,
    "i32" => Int32,
    "i64" => Int64,
    "u8" => UInt8,
    "u16" => UInt16,
    "u32" => UInt32,
    "u64" => UInt64,
    "f32" => Cfloat,
    "f64" => Cdouble,
    "usize" => Csize_t,
    "isize" => Int,
    "bool" => Bool,
    "c_void" => Cvoid,
    "std::ffi::c_void" => Cvoid,
    "core::ffi::c_void" => Cvoid
)

function _clean_ws(s::AbstractString)
    return strip(replace(String(s), r"\s+" => " "))
end

function _parse_rust_type(raw::AbstractString)
    s = _clean_ws(raw)
    s == "" && return Cvoid

    if startswith(s, "*const ")
        inner = strip(s[length("*const ") + 1:end])
        return Ptr{_parse_rust_type(inner)}
    elseif startswith(s, "*mut ")
        inner = strip(s[length("*mut ") + 1:end])
        return Ptr{_parse_rust_type(inner)}
    end

    if haskey(RUST_TYPE_MAP, s)
        return RUST_TYPE_MAP[s]
    end

    throw(ArgumentError("unsupported Rust FFI type '$raw'. MVP supports primitives and raw pointers like *const f64 / *mut i32."))
end

function _parse_arg(raw::AbstractString)
    p = _clean_ws(raw)
    p == "" && return nothing

    m = match(r"^(?:mut\s+)?([A-Za-z_]\w*)\s*:\s*(.+)$", p)
    m === nothing && throw(ArgumentError("unsupported Rust argument syntax '$raw'. Expected `name: type`."))

    name = String(m.captures[1])
    typ = _parse_rust_type(m.captures[2])
    return (name, typ)
end

"""
    parse_signatures(code::AbstractString)

Parse Lena-Rust exported functions marked as:

```rust
@export
fn add_i32(a: i32, b: i32) -> i32 {
    a + b
}
```
"""
function parse_signatures(code::AbstractString)
    stripped = replace(String(code), r"/\*.*?\*/"s => "")
    stripped = replace(stripped, r"//.*" => "")

    pattern = r"@export\s+(?:pub\s+)?(?:unsafe\s+)?(?:extern\s+\"C\"\s+)?fn\s+([A-Za-z_]\w*)\s*\(([^)]*)\)\s*(?:->\s*([^\{]+?))?\s*\{"
    signatures = RustSignature[]

    for m in eachmatch(pattern, stripped)
        fname = String(m.captures[1])
        args_raw = _clean_ws(m.captures[2])
        ret_raw = m.captures[3] === nothing ? "()" : _clean_ws(m.captures[3])

        args = Tuple{String, Any}[]
        if args_raw != ""
            for raw_arg in split(args_raw, ',')
                parsed = _parse_arg(raw_arg)
                parsed === nothing && continue
                push!(args, parsed)
            end
        end

        arg_names = [a[1] for a in args]
        arg_types = tuple((a[2] for a in args)...)
        ret_type = _parse_rust_type(ret_raw)
        push!(signatures, RustSignature(Symbol(fname), ret_type, arg_types, arg_names, m.match))
    end

    return signatures
end

function _to_c_signatures(signatures::Vector{RustSignature})
    return [C.CSignature(sig.name, sig.return_type, sig.arg_types, sig.arg_names, sig.source) for sig in signatures]
end

function _generate_ffi_code(code::AbstractString)
    # Lena-Rust syntax:
    #
    #   @export
    #   fn add_i32(a: i32, b: i32) -> i32 { ... }
    #
    # becomes Rust 2021 FFI:
    #
    #   #[no_mangle]
    #   pub extern "C" fn add_i32(a: i32, b: i32) -> i32 { ... }
    #
    # We intentionally use edition = "2021" in Cargo.toml, so plain
    # #[no_mangle] is accepted. This keeps the MVP compatible with more Rust setups.
    return replace(String(code), r"@export\s+(?:pub\s+)?(?:unsafe\s+)?(?:extern\s+\"C\"\s+)?" => "#[no_mangle]\npub extern \"C\" ")
end

function _digest(parts...)
    joined = join(string.(parts), "\0")
    return bytes2hex(sha1(joined))
end

function _sanitize_crate_base(name::AbstractString)
    base = lowercase(replace(String(name), r"[^A-Za-z0-9_]" => "_"))
    isempty(base) && (base = "inline")
    if match(r"^[A-Za-z_]", base) === nothing
        base = "lena_" * base
    end
    return base
end

function _crate_name(name::AbstractString, hash::AbstractString)
    return _sanitize_crate_base(name) * "_" * hash[1:12]
end

function _cargo()
    return get(ENV, "CARGO", "cargo")
end

function _write_cargo_project(build_dir::AbstractString, crate_name::AbstractString, rust_code::AbstractString)
    src_dir = joinpath(build_dir, "src")
    mkpath(src_dir)

    cargo_toml = """
[package]
name = "$(crate_name)"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
"""

    write(joinpath(build_dir, "Cargo.toml"), cargo_toml)
    write(joinpath(src_dir, "lib.rs"), rust_code)
end

function _cargo_build(build_dir::AbstractString; flags::Vector{String}=String[])
    cargo = _cargo()
    Sys.which(cargo) === nothing && throw(ErrorException("Lena.Rust could not find Cargo. Install Rust/Cargo or set ENV[\"CARGO\"] to cargo path."))

    cmd_parts = String[cargo, "build", "--release", "--manifest-path", joinpath(build_dir, "Cargo.toml")]
    append!(cmd_parts, flags)

    try
        cmd = Cmd(cmd_parts)
        run(Cmd(cmd; dir=build_dir))
    catch err
        throw(ErrorException("Lena.Rust failed to build Rust provider. Command was: $(join(cmd_parts, ' '))\nOriginal error: $err"))
    end
end

function _rust_libpath(build_dir::AbstractString, crate_name::AbstractString)
    release_dir = joinpath(build_dir, "target", "release")

    filename = if Sys.iswindows()
        crate_name * "." * Libdl.dlext
    else
        "lib" * crate_name * "." * Libdl.dlext
    end

    path = joinpath(release_dir, filename)
    isfile(path) && return path

    candidates = isdir(release_dir) ? filter(f -> endswith(f, "." * Libdl.dlext), readdir(release_dir)) : String[]
    throw(ErrorException("Lena.Rust built the crate, but could not find dynamic library '$filename' in $release_dir. Found: $(join(candidates, ", "))"))
end

"""
    inline(code::AbstractString; name="inline", cargo_flags=String[])

Compile inline Lena-Rust code into a Rust `cdylib` and return a `RustProvider`.

Export functions with Lena's `@export` marker:

```julia
```julia
code = "@export\nfn add_i32(a: i32, b: i32) -> i32 {\n    a + b\n}\n"
rs = Lena.Rust.inline(code)


rs.add_i32(Int32(1), Int32(2))
```
"""
function inline(code::AbstractString; name::AbstractString="inline", cargo_flags::Vector{String}=String[])
    signatures = parse_signatures(code)
    isempty(signatures) && throw(ArgumentError("Lena.Rust.inline found no exported Rust functions. Mark exported functions with `@export`."))

    rust_code = _generate_ffi_code(code)
    hash = _digest(rust_code, join(cargo_flags, "\0"), VERSION)
    crate_name = _crate_name(name, hash)

    build_dir = joinpath(C.cache_root(), "rust", hash)
    mkpath(build_dir)

    _write_cargo_project(build_dir, crate_name, rust_code)
    _cargo_build(build_dir; flags=cargo_flags)

    libpath = _rust_libpath(build_dir, crate_name)
    inner = C._provider_from_library(libpath, _to_c_signatures(signatures), build_dir)
    sigdict = Dict(sig.name => sig for sig in signatures)

    return RustProvider(inner, sigdict, build_dir, crate_name)
end

end # module Rust
