module C

using Libdl
using SHA
using TOML
import ..AbstractProvider

export CProvider, CFunction, CSignature, inline, load, import_project, var"import"

const CACHE_ROOT = Ref{String}(joinpath(homedir(), ".julia", "lena", "cache"))

const EXPORT_HEADER = raw"""
#ifndef LENA_EXPORT
#  if defined(_WIN32) || defined(__CYGWIN__)
#    define LENA_EXPORT __declspec(dllexport)
#  else
#    define LENA_EXPORT __attribute__((visibility("default")))
#  endif
#endif
"""

"""
    CSignature

A parsed C function signature.
"""
struct CSignature
    name::Symbol
    return_type::Any
    arg_types::Tuple
    arg_names::Vector{String}
    source::String
end

"""
    CFunction

Callable wrapper around a loaded C function pointer.
"""
struct CFunction{Ret, ArgTypes}
    ptr::Ptr{Cvoid}
    name::Symbol
    signature::CSignature
end

function _cfunction(ptr::Ptr{Cvoid}, name::Symbol, signature::CSignature)
    arg_tuple_type = Tuple{signature.arg_types...}
    return CFunction{signature.return_type, arg_tuple_type}(ptr, name, signature)
end

@generated function (fn::CFunction{Ret, ArgTuple})(args...) where {Ret, ArgTuple}
    if !(ArgTuple <: Tuple)
        throw(ArgumentError("internal Lena.C error: CFunction argument signature is not a Tuple type"))
    end

    arg_types = ArgTuple.parameters
    n = length(arg_types)

    arg_tuple_expr = Expr(:tuple, arg_types...)
    call_args = [:(Base.convert($(arg_types[i]), args[$i])) for i in 1:n]

    return quote
        if length(args) != $n
            throw(ArgumentError("wrong number of arguments for C function: expected $($n), got $(length(args))"))
        end

        ccall(fn.ptr, $Ret, $arg_tuple_expr, $(call_args...))
    end
end

function Base.show(io::IO, fn::CFunction)
    sig = fn.signature
    print(io, "Lena.C.CFunction(", sig.name, ")")
end

"""
    CProvider

Provider returned by `@c`, `Lena.C.inline`, or `Lena.C.load`.
"""
struct CProvider <: AbstractProvider
    libpath::String
    handle::Ptr{Cvoid}
    functions::Dict{Symbol, Any}
    signatures::Dict{Symbol, CSignature}
    build_dir::String
end

function Base.getproperty(provider::CProvider, name::Symbol)
    if name in (:libpath, :handle, :functions, :signatures, :build_dir)
        return getfield(provider, name)
    end
    funcs = getfield(provider, :functions)
    if haskey(funcs, name)
        return funcs[name]
    end
    return getfield(provider, name)
end

function Base.propertynames(provider::CProvider; private::Bool=false)
    exported = Tuple(keys(getfield(provider, :functions)))
    base = (:libpath, :handle, :functions, :signatures, :build_dir)
    return private ? (base..., exported...) : exported
end

function Base.show(io::IO, provider::CProvider)
    print(io, "Lena.C.CProvider(", length(provider.functions), " function")
    length(provider.functions) == 1 || print(io, "s")
    print(io, ", lib=", provider.libpath, ")")
end

function cache_root(path::AbstractString)
    CACHE_ROOT[] = String(path)
    mkpath(CACHE_ROOT[])
    return CACHE_ROOT[]
end

function cache_root()
    mkpath(CACHE_ROOT[])
    return CACHE_ROOT[]
end

function _digest(parts...)
    joined = join(string.(parts), "\0")
    return bytes2hex(sha1(joined))
end

function _shared_ext()
    return "." * Libdl.dlext
end

function _compiler()
    if haskey(ENV, "CC")
        return ENV["CC"]
    end
    return Sys.iswindows() ? "gcc" : "cc"
end

function _compile_shared(source_files::Vector{String}, libpath::String; include_dirs::Vector{String}=String[], flags::Vector{String}=String[])
    cc = _compiler()
    cmd_parts = String[cc]

    if Sys.isapple()
        append!(cmd_parts, ["-dynamiclib", "-O2"])
    elseif Sys.iswindows()
        append!(cmd_parts, ["-shared", "-O2"])
    else
        append!(cmd_parts, ["-shared", "-fPIC", "-O2"])
    end

    for dir in include_dirs
        push!(cmd_parts, "-I" * dir)
    end

    append!(cmd_parts, flags)
    append!(cmd_parts, source_files)
    append!(cmd_parts, ["-o", libpath])

    cmd = Cmd(cmd_parts)
    try
        run(cmd)
    catch err
        throw(ErrorException("Lena.C failed to compile C provider. Command was: $(join(cmd_parts, ' '))\nOriginal error: $err"))
    end
    return libpath
end

const SIMPLE_TYPES = Dict{String, Any}(
    "void" => Cvoid,
    "char" => Cchar,
    "signed char" => Cchar,
    "unsigned char" => Cuchar,
    "short" => Cshort,
    "unsigned short" => Cushort,
    "int" => Cint,
    "unsigned int" => Cuint,
    "long" => Clong,
    "unsigned long" => Culong,
    "long long" => Clonglong,
    "unsigned long long" => Culonglong,
    "float" => Cfloat,
    "double" => Cdouble,
    "size_t" => Csize_t,
    "ptrdiff_t" => Cptrdiff_t,
    "int8_t" => Int8,
    "uint8_t" => UInt8,
    "int16_t" => Int16,
    "uint16_t" => UInt16,
    "int32_t" => Int32,
    "uint32_t" => UInt32,
    "int64_t" => Int64,
    "uint64_t" => UInt64,
    "intptr_t" => Int,
    "uintptr_t" => UInt
)

function _clean_ws(s::AbstractString)
    return strip(replace(String(s), r"\s+" => " "))
end

function _remove_param_name(param::AbstractString)
    s = _clean_ws(replace(String(param), r"\[[^\]]*\]" => " *"))
    s = replace(s, r"\s*=.*$" => "")
    s = _clean_ws(s)
    if s == "" || s == "void"
        return s
    end
    # Remove a trailing C identifier which is most likely the parameter name.
    if occursin(r"[A-Za-z_]\w*$", s)
        without_name = replace(s, r"\s*[A-Za-z_]\w*$" => "")
        without_name = _clean_ws(without_name)
        if without_name != "" && (occursin("*", without_name) || haskey(SIMPLE_TYPES, replace(without_name, r"\b(const|volatile|restrict)\b" => "") |> _clean_ws))
            return without_name
        end
        parts = split(s, ' ')
        if length(parts) > 1
            candidate = _clean_ws(join(parts[1:end-1], ' '))
            cleaned = _clean_ws(replace(candidate, r"\b(const|volatile|restrict)\b" => ""))
            if haskey(SIMPLE_TYPES, cleaned) || occursin("*", candidate)
                return candidate
            end
        end
    end
    return s
end

function _parse_c_type(raw::AbstractString; is_argument::Bool=true)
    original = _clean_ws(raw)
    s = _remove_param_name(original)
    is_const_char_ptr = occursin(r"\bconst\b", s) && occursin(r"\bchar\b", s) && occursin("*", s)
    pointer_count = count(==('*'), s)
    base = replace(s, "*" => " ")
    base = replace(base, r"\b(const|volatile|restrict)\b" => "")
    base = _clean_ws(base)

    if pointer_count > 0
        if base == "char" && is_argument && is_const_char_ptr
            return Cstring
        elseif base == "char" && !is_argument
            return Cstring
        end
        base_type = get(SIMPLE_TYPES, base, Cvoid)
        typ = base_type === Cvoid ? Ptr{Cvoid} : Ptr{base_type}
        for _ in 2:pointer_count
            typ = Ptr{typ}
        end
        return typ
    end

    if haskey(SIMPLE_TYPES, base)
        return SIMPLE_TYPES[base]
    end

    throw(ArgumentError("unsupported C type '$raw' parsed as '$base'. Add it to SIMPLE_TYPES or wrap it as a pointer."))
end

function _parse_arg(param::AbstractString)
    p = _clean_ws(param)
    if p == "" || p == "void"
        return nothing
    end
    name_match = match(r"([A-Za-z_]\w*)\s*(?:\[[^\]]*\])?$", p)
    name = name_match === nothing ? "arg" : name_match.captures[1]
    typ = _parse_c_type(p; is_argument=true)
    return (name, typ)
end

function parse_signatures(text::AbstractString; only::Union{Nothing, Set{String}}=nothing)
    stripped = replace(String(text), r"/\*.*?\*/"s => "")
    stripped = replace(stripped, r"//.*" => "")

    pattern = r"(?:LENA_EXPORT\s+)?([A-Za-z_][A-Za-z0-9_\s\*]*?)\s+([A-Za-z_]\w*)\s*\(([^;{}()]*)\)\s*(?:;|\{)"
    signatures = CSignature[]

    for m in eachmatch(pattern, stripped)
        ret_raw = _clean_ws(m.captures[1])
        fname = String(m.captures[2])
        args_raw = _clean_ws(m.captures[3])

        if only !== nothing && !(fname in only)
            continue
        end

        args = Tuple{String, Any}[]
        if args_raw != "" && args_raw != "void"
            for raw_arg in split(args_raw, ',')
                parsed = _parse_arg(raw_arg)
                parsed === nothing && continue
                push!(args, parsed)
            end
        end

        arg_names = [a[1] for a in args]
        arg_types = tuple((a[2] for a in args)...)
        ret_type = _parse_c_type(ret_raw; is_argument=false)
        push!(signatures, CSignature(Symbol(fname), ret_type, arg_types, arg_names, m.match))
    end

    return signatures
end

function _provider_from_library(libpath::AbstractString, signatures::Vector{CSignature}, build_dir::AbstractString)
    handle = Libdl.dlopen(String(libpath))
    functions = Dict{Symbol, Any}()
    sigdict = Dict{Symbol, CSignature}()

    for sig in signatures
        ptr = try
            Libdl.dlsym(handle, sig.name)
        catch err
            throw(ErrorException("Lena.C could not find exported symbol '$(sig.name)' in $(libpath). Make sure it is exported with LENA_EXPORT or visible in the shared library. Original error: $err"))
        end
        functions[sig.name] = _cfunction(ptr, sig.name, sig)
        sigdict[sig.name] = sig
    end

    return CProvider(String(libpath), handle, functions, sigdict, String(build_dir))
end

"""
    inline(code::AbstractString; name="inline", flags=String[])

Build inline C code into a shared library and return a `CProvider`.

Functions should be marked with `LENA_EXPORT` so Lena can discover them.
"""
function inline(code::AbstractString; name::AbstractString="inline", flags::Vector{String}=String[])
    full_code = EXPORT_HEADER * "\n" * String(code)
    signatures = parse_signatures(full_code)
    isempty(signatures) && throw(ArgumentError("Lena.C.inline found no C functions. Mark exported functions with LENA_EXPORT."))

    hash = _digest(full_code, join(flags, "\0"), VERSION)
    build_dir = joinpath(cache_root(), "c", hash)
    mkpath(build_dir)

    source_path = joinpath(build_dir, "source.c")
    libpath = joinpath(build_dir, "lib" * String(name) * _shared_ext())

    write(source_path, full_code)
    _compile_shared([source_path], libpath; include_dirs=[build_dir], flags=flags)
    return _provider_from_library(libpath, signatures, build_dir)
end

function _as_string_vector(value, default=String[])
    value === nothing && return copy(default)
    return String.(value)
end

function _read_project_config(path::AbstractString)
    toml_path = joinpath(path, "Lena.toml")
    isfile(toml_path) || throw(ArgumentError("C project import expects a Lena.toml file at $(toml_path)"))
    return TOML.parsefile(toml_path)
end

"""
    load(path::AbstractString; flags=String[])
    import_project(path::AbstractString; flags=String[])
    var"import"(path::AbstractString; flags=String[])

Build and load a C project described by `Lena.toml`.

Expected project layout:

```text
native_mylib/
├─ Lena.toml
├─ include/mylib.h
└─ src/mylib.c
```

`Lena.toml` example:

```toml
name = "mylib"
language = "c"
headers = ["include/mylib.h"]
sources = ["src/mylib.c"]
include_dirs = ["include"]
exports = ["add_i32"]
```
"""
function load(path::AbstractString; flags::Vector{String}=String[])
    root = abspath(String(path))
    cfg = _read_project_config(root)

    get(cfg, "language", "c") == "c" || throw(ArgumentError("Lena.C.load currently supports only language = \"c\""))

    name = String(get(cfg, "name", basename(root)))
    headers = _as_string_vector(get(cfg, "headers", String[]))
    sources = _as_string_vector(get(cfg, "sources", String[]))
    include_dirs = _as_string_vector(get(cfg, "include_dirs", ["include"]))
    exports = Set(String.(get(cfg, "exports", String[])))

    isempty(sources) && throw(ArgumentError("Lena.C.load requires `sources` in Lena.toml"))
    isempty(headers) && throw(ArgumentError("Lena.C.load requires at least one header in `headers` for signature parsing"))

    abs_headers = [joinpath(root, h) for h in headers]
    abs_sources = [joinpath(root, s) for s in sources]
    abs_includes = [joinpath(root, d) for d in include_dirs]

    for file in vcat(abs_headers, abs_sources)
        isfile(file) || throw(ArgumentError("C project file does not exist: $file"))
    end

    signature_text = join(read.(abs_headers, String), "\n")
    only = isempty(exports) ? nothing : exports
    signatures = parse_signatures(signature_text; only=only)
    isempty(signatures) && throw(ArgumentError("Lena.C.load found no matching function signatures in headers. Add prototypes and/or `exports` in Lena.toml."))

    hash_parts = String[read(joinpath(root, "Lena.toml"), String)]
    append!(hash_parts, [read(h, String) for h in abs_headers])
    append!(hash_parts, [read(s, String) for s in abs_sources])
    push!(hash_parts, join(flags, "\0"))

    hash = _digest(hash_parts...)
    build_dir = joinpath(cache_root(), "c_project", hash)
    mkpath(build_dir)

    export_header_path = joinpath(build_dir, "lena_export.h")
    write(export_header_path, EXPORT_HEADER)

    libpath = joinpath(build_dir, "lib" * name * _shared_ext())
    _compile_shared(abs_sources, libpath; include_dirs=vcat(abs_includes, build_dir), flags=flags)
    return _provider_from_library(libpath, signatures, build_dir)
end

const import_project = load
const var"import" = load

end # module C
