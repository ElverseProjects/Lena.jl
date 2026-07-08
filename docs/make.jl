using Documenter
using Lena

makedocs(
    sitename = "Lena.jl",
    modules = [Lena],
    pages = [
        "Home" => "index.md",
    ],
)
