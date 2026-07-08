using Lena

mylib = Lena.C.load(joinpath(@__DIR__, "native_mylib"))

println(mylib.add_i32(Int32(1), Int32(2)))
println(mylib.mul_f64(2.0, 4.0))
println(mylib.clamp_i32(Int32(300), Int32(0), Int32(255)))
