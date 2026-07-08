import PythonCall

"""
    PythonProvider(code::AbstractString; name="__lena_inline__")

Provider object returned by `@python`.
"""
struct PythonProvider <: AbstractProvider
    namespace::Any
    code::String
end

function PythonProvider(code::AbstractString; name::AbstractString="__lena_inline__")
    types = PythonCall.pyimport("types")
    builtins = PythonCall.pyimport("builtins")
    mod = types.ModuleType(name)
    builtins.exec(String(code), mod.__dict__)
    return PythonProvider(mod, String(code))
end

function Base.getproperty(provider::PythonProvider, name::Symbol)
    if name === :namespace || name === :code
        return getfield(provider, name)
    end
    return getproperty(getfield(provider, :namespace), name)
end

function Base.propertynames(provider::PythonProvider; private::Bool=false)
    names = try
        builtins = PythonCall.pyimport("builtins")
        Symbol.(PythonCall.pyconvert(Vector{String}, PythonCall.pylist(builtins.dir(getfield(provider, :namespace)))))
    catch
        Symbol[]
    end
    public_names = filter(n -> !startswith(String(n), "__"), names)
    base = (:namespace, :code)
    return private ? (base..., public_names...) : Tuple(public_names)
end

function Base.show(io::IO, provider::PythonProvider)
    print(io, "Lena.PythonProvider(")
    names = propertynames(provider)
    print(io, length(names), " public name")
    length(names) == 1 || print(io, "s")
    print(io, ")")
end
