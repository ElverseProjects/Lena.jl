using Test
using Lena
import PythonCall

@testset "Lena.jl basics" begin
    @test Lena.AbstractProvider !== nothing
    @test hasmethod(Lena.C.inline, Tuple{AbstractString})
    @test hasmethod(Lena.C.load, Tuple{AbstractString})
end

@testset "C signature parser" begin
    sigs = Lena.C.parse_signatures("""
    #include <stdint.h>
    LENA_EXPORT int32_t add_i32(int32_t a, int32_t b);
    LENA_EXPORT double mul_f64(double a, double b);
    """)

    @test length(sigs) == 2
    @test sigs[1].name == :add_i32
    @test sigs[1].return_type == Int32
    @test sigs[1].arg_types == (Int32, Int32)
    @test sigs[2].name == :mul_f64
    @test sigs[2].return_type == Cdouble
end

@testset "Inline C smoke test" begin
    c = @c """
    #include <stdint.h>

    LENA_EXPORT int32_t add_i32(int32_t a, int32_t b) {
        return a + b;
    }
    """

    @test c.add_i32(Int32(10), Int32(20)) == Int32(30)
end

@testset "Inline Python smoke test" begin
    py = @python """
def add(a, b):
    return a + b
"""

    @test PythonCall.pyconvert(Int, py.add(10, 20)) == 30
end

@testset "Inline Rust smoke test" begin
    if Sys.which("cargo") === nothing
        @info "Skipping Inline Rust smoke test: Cargo was not found"
    else
        rs = @rust """
@export
fn add_i32(a: i32, b: i32) -> i32 {
    a + b
}

@export
fn mul_f64(a: f64, b: f64) -> f64 {
    a * b
}
"""

        @test rs.add_i32(Int32(10), Int32(20)) == Int32(30)
        @test rs.mul_f64(2.0, 4.0) == 8.0
    end
end

@testset "Rust import smoke test" begin
    rs = Lena.Rust.load(joinpath(@__DIR__, "..", "examples", "native_rust_mylib"))

    @test rs.add_i32(Int32(10), Int32(20)) == Int32(30)
    @test rs.mul_f64(2.5, 4.0) == 10.0
    @test rs.clamp_i32(Int32(300), Int32(0), Int32(255)) == Int32(255)
end

