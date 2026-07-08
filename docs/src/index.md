# Lena.jl

A Julia DSL for provider-based multilingual integration.

```julia
using Lena

py = @python """
def add(a, b):
    return a + b
"""

c = @c """
#include <stdint.h>
LENA_EXPORT int32_t add_i32(int32_t a, int32_t b) { return a + b; }
"""
```
