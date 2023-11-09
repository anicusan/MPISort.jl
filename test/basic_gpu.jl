# File   : basic.jl
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

# Generate local GPU array on each MPI rank - even with different number of elements
rng = Xoshiro(rank)
num_elements = 50 + rank * 2
local_array = CuArray(rand(rng, 1:500, num_elements))

# Sort arrays across all MPI ranks
alg = SIHSort(comm)
sorted_local_array = mpisort!(local_array; alg=alg)

# Print each local array sequentially
for i in 0:nranks - 1
    rank == i && @show rank sorted_local_array alg.stats
    MPI.Barrier(comm)
end
