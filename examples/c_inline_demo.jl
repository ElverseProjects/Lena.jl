using Lena

py = @python """
def square(x):
    return x * x

def greet(name):
    return f"Hello, {name}!"
"""

c = @c """
#include <stdint.h>

LENA_EXPORT int32_t add_i32(int32_t a, int32_t b) {
    return a + b;
}

LENA_EXPORT double mul_f64(double a, double b) {
    return a * b;
}
"""

println(py.greet("Lena"))
println(py.square(12))
println(c.add_i32(Int32(10), Int32(20)))
println(c.mul_f64(2.5, 4.0))
