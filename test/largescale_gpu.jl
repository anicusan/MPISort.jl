# File   : largescale.jl
# License: MIT
# Author : Andrei Leonard Nicusan <a.l.nicusan@gmail.com>
# Date   : 13.10.2022


using MPI
using MPISort
using Random

using CUDA


# Initialise MPI, get communicator for all ranks, rank index, number of ranks
MPI.Init()

comm = MPI.COMM_WORLD
rank = MPI.Comm_rank(comm)
nranks = MPI.Comm_size(comm)


function largescale(num_elements=500_000)

    # Generate local array on each MPI rank - even with different number of elements
    rng = Xoshiro(rank)
    num_elements = 500_000 + rank * (num_elements ÷ 20)
    local_array = CuArray(rand(rng, Int32(1):Int32(10 * num_elements), num_elements))

    # Sort arrays across all MPI ranks
    alg = SIHSort(comm)
    @time sorted_local_array = mpisort!(local_array; alg=alg)

    # Print each local array sequentially
    for i in 0:nranks - 1
        rank == i && @show rank alg.stats
        MPI.Barrier(comm)
    end
end


# Run once to compile everything, then again to benchmark
rank == 0 && println("First run, compiling...")
largescale()

rank == 0 && println("Single benchmark run")
largescale()
