using Lena

rs = @rust """
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
"""

println(rs.add_i32(Int32(10), Int32(20)))  # 30
println(rs.mul_f64(2.0, 4.0))             # 8.0
println(rs.clamp_i32(Int32(300), Int32(0), Int32(255))) # 255
