#include "mylib.h"

int32_t add_i32(int32_t a, int32_t b) {
    return a + b;
}

double mul_f64(double a, double b) {
    return a * b;
}

int32_t clamp_i32(int32_t x, int32_t lo, int32_t hi) {
    if (x < lo) return lo;
    if (x > hi) return hi;
    return x;
}
