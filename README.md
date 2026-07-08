# Lena.jl

**A Julia DSL for provider-based multilingual integration.**

Lena.jl is an experimental Julia package for embedding, building, importing, and calling code from other languages directly from Julia.

Current MVP providers:

- inline Python via `@python """..."""`
- inline C via `@c """..."""`
- C project import via `Lena.C.load(path)` / `Lena.C.import_project(path)` / `Lena.C.var"import"(path)`

> Note: `import` is a Julia keyword. Some Julia versions/parsing contexts may not accept `Lena.C.import(path)` syntax directly. The stable public spelling in this MVP is `Lena.C.load(path)`. The keyword-style alias is available as `Lena.C.var"import"(path)`.

## Installation for local development

From Julia package mode:

```julia
pkg> dev /path/to/Lena.jl
pkg> instantiate
pkg> test Lena
```

## Inline Python

```julia
using Lena

py = @python """
def greet(name):
    return f"Hello, {name}!"

def add(a, b):
    return a + b
"""

println(py.greet("Lena"))
println(py.add(2, 3))
```

Internally this uses PythonCall.jl.

## Inline C

```julia
using Lena

c = @c """
#include <stdint.h>

LENA_EXPORT int32_t add_i32(int32_t a, int32_t b) {
    return a + b;
}

LENA_EXPORT double mul_f64(double a, double b) {
    return a * b;
}
"""

println(c.add_i32(Int32(10), Int32(20)))
println(c.mul_f64(2.5, 4.0))
```

The `@c` macro:

1. writes the C code into Lena's build cache;
2. compiles it into a shared library;
3. loads the library through `Libdl`;
4. wraps exported functions as Julia-callable provider properties.

Functions meant to be visible to Lena should be marked with `LENA_EXPORT`.

## C project import

Expected layout:

```text
native_mylib/
├─ Lena.toml
├─ include/
│  └─ mylib.h
└─ src/
   └─ mylib.c
```

`Lena.toml`:

```toml
name = "mylib"
language = "c"
headers = ["include/mylib.h"]
sources = ["src/mylib.c"]
include_dirs = ["include"]
exports = ["add_i32", "mul_f64"]
```

Usage:

```julia
using Lena

mylib = Lena.C.load("examples/native_mylib")

println(mylib.add_i32(Int32(1), Int32(2)))
println(mylib.mul_f64(2.0, 4.0))
```

## Design direction

The core abstraction is a **provider**:

```text
Python code  -> PythonProvider -> py.some_function(...)
C code       -> CProvider      -> c.some_function(...)
C directory  -> CProvider      -> mylib.some_function(...)
```

The long-term goal is to grow this into a provider-oriented DSL for Julia:

```julia
using Lena

py = @python """ ... """
c  = @c """ ... """
native = Lena.C.load("./native")

py.transform(...)
c.kernel(...)
native.fast_function(...)
```

## Current limitations

This is a first MVP, intentionally small and controlled.

C parser limitations:

- supports simple C prototypes/functions;
- supports common primitive C types and pointers;
- does not support structs, typedef expansion, callbacks, function pointers, C++ or macros-as-API yet;
- for serious headers, a future Clang.jl backend is the right next step.

Runtime limitations:

- requires a working C compiler (`cc`, `gcc`, `clang`, or `ENV["CC"]`);
- shared library behavior differs across Linux, macOS, and Windows;
- C/Python code is executed on the user's machine and should be treated as trusted code.

## Repository description

Recommended GitHub description:

> A Julia DSL for provider-based multilingual integration.
