@export
fn add_i32(a: i32, b: i32) -> i32 {
    a + b
}

@export
fn mul_f64(a: f64, b: f64) -> f64 {
    a * b
}

@export
fn clamp_i32(x: i32, lo: i32, hi: i32) -> i32 {
    if x < lo {
        lo
    } else if x > hi {
        hi
    } else {
        x
    }
}
