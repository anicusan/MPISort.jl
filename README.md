# MPISort

[![Build Status](https://github.com/anicusan/MPISort.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/anicusan/MPISort.jl/actions/workflows/CI.yml?query=branch%3Amain)


MPI-based sorting algorithms for the Julia ecosystem:


## `SIHSort`

Sampling with interpolated histograms sorting algorithm (pronounced _sigh_ sort like anything
MPI-related), optimised for minimum inter-rank communication. Features:

- **Does not require that distributed data fits into the memory of a single node**. No IO.
- Works for any comparison-based data, with additional optimisations for numeric elements.
- Optimised for minimum MPI communication; can use Julia threads on each shared-memory node.
- The node-local arrays may have different sizes; sorting will try to balance number of elements held by each MPI rank.
- Implements the standard Julia `sort!` API, and naturally works for custom data, comparisons, orderings, etc.


### Example

```julia

using MPI
using MPISort


# Initialise MPI, get communicator for all ranks, rank index, number of ranks
MPI.Init()

comm = MPI.COMM_WORLD
rank = MPI.Comm_rank(comm)
nranks = MPI.Comm_size(comm)

# Generate local array on each MPI rank - even with different number of elements
num_elements = 50 + rank * 2
local_array = rand(1:500, num_elements)

# Sort arrays across all MPI ranks
alg = SIHSort(comm)
sorted_local_array = sort!(local_array; alg=alg)

# Print each local array sequentially
for i in 1:nranks
    rank == i && @show rank sorted_local_array alg.stats
    MPI.Barrier()
end

```


This algorithm, builds strongly on prior art:

- _Harsh V, Kale L, Solomonik E. Histogram sort with sampling._ : followed main ideas and theoretical results, with original communication and interpolation optimisations.
- _Sundar H, Malhotra D, Biros G. Hyksort: a new variant of hypercube quicksort on distributed memory architectures._
- _Shi H, Schaeffer J. Parallel sorting by regular sampling._
- _Solomonik E, Kale LV. Highly scalable parallel sorting._
- John Lapeyre, integer base-2 logarithm - https://github.com/jlapeyre/ILog2.jl.


# License

`MPISort.jl` is MIT-licensed. Enjoy.

