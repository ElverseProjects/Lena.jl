using Lena

# Load a Lena-Rust project from a directory.
# The directory must contain Lena.toml and Rust source files with @export markers.
rs = Lena.Rust.load(joinpath(@__DIR__, "native_rust_mylib"))

println("add_i32(10, 20) = ", rs.add_i32(Int32(10), Int32(20)))
println("mul_f64(2.5, 4.0) = ", rs.mul_f64(2.5, 4.0))
println("clamp_i32(300, 0, 255) = ", rs.clamp_i32(Int32(300), Int32(0), Int32(255)))
