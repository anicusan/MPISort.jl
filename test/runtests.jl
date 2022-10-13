using MPI
using MPISort
using Test

@testset "basic" begin
    np = 2
    mpiexec() do exe
        p = run(`$exe -n $np $(Base.julia_cmd()) basic.jl`)
        @test success(p)
    end
end
