module Python

import ..AbstractProvider
import Base: getproperty, propertynames

struct PythonProvider <: AbstractProvider
    namespace::Any
    code::String
end

"""
    _pythoncall()

Load PythonCall lazily.

Important: do not put `using PythonCall` at the top of this file.
Otherwise `using Lena` will require Python immediately.
"""
function _pythoncall()
    if !isdefined(@__MODULE__, :PythonCall)
        @eval import PythonCall
    end

    return getfield(@__MODULE__, :PythonCall)
end

"""
    inline(code::AbstractString)

Execute inline Python code and return a provider object.

PythonCall is loaded only here, not when `using Lena` runs.
"""
function inline(code::AbstractString)
    PC = _pythoncall()

    builtins = PC.pyimport("builtins")
    namespace = builtins.dict()

    builtins.exec(String(code), namespace)

    return PythonProvider(namespace, String(code))
end

function Base.getproperty(provider::PythonProvider, name::Symbol)
    if name === :namespace || name === :code
        return getfield(provider, name)
    end

    namespace = getfield(provider, :namespace)
    return namespace[String(name)]
end

function Base.propertynames(provider::PythonProvider; private::Bool=false)
    if private
        return (:namespace, :code)
    end

    # Keep it simple for now. Python namespace introspection can be improved later.
    return (:namespace, :code)
end

end
