# MPISort
_Don't put all your eggs in one basket!_

[![CI](https://github.com/anicusan/MPISort.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/anicusan/MPISort.jl/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/anicusan/MPISort.jl)](https://github.com/anicusan/MPISort.jl)
[![DevDocs](https://img.shields.io/badge/docs-dev-blue.svg)](https://anicusan.github.io/MPISort.jl/dev/)


Sorting $N$ elements spread out across $P$ processors, _with no processor being able to hold all
elements at once_ is a difficult problem, with very few open-source implementations in
[C++](https://github.com/hsundar/usort) and [Charm++](https://github.com/vipulharsh/HSS). This
library provides the `mpisort!` function for distributed MPI-based sorting algorithms following the
standard Julia `Base.sort!` signature; at the moment, one optimised algorithm is provided:


## `SIHSort`

Sampling with interpolated histograms sorting algorithm (pronounced _sigh_ sort, like anything
MPI-related), optimised for minimum inter-rank communication and memory footprint. Features:

- **Does not require that distributed data fits into the memory of a single node**. No IO either.
- Works for any comparison-based data, with additional optimisations for numeric elements.
- Optimised for minimum MPI communication; can use Julia threads on each shared-memory node.
- The node-local arrays may have different sizes; sorting will try to balance the number of elements held by each MPI rank.
- Works with any `AbstractVector`, including accelerators such as GPUs (see Note).
- Implements the standard Julia `sort!` API, and naturally works for custom data, comparisons, orderings, etc.


### Example

```julia
# File:   mpisort.jl
# Run as: mpiexec -n 4 julia --threads=2 mpisort.jl

using MPI
using MPISort
using Random


# Initialise MPI, get communicator for all ranks, rank index, number of ranks
MPI.Init()

comm = MPI.COMM_WORLD
rank = MPI.Comm_rank(comm)
nranks = MPI.Comm_size(comm)

# Generate local array on each MPI rank - even with different number of elements
rng = Xoshiro(rank)
num_elements = 50 + rank * 2
local_array = rand(rng, 1:500, num_elements)

# Sort arrays across all MPI ranks
alg = SIHSort(comm)
sorted_local_array = mpisort!(local_array; alg=alg)

# Print each local array sequentially
for i in 0:nranks - 1
    rank == i && @show rank sorted_local_array alg.stats
    MPI.Barrier(comm)
end

```

**Note:** because the data is redistributed between nodes, the vector size must change - hence it
is different to the in-place `Base.sort!`. The input vector is mutated, but another vector - with
potentially different size and elements - is returned. This is the reason for a different function
signature (`mpisort!` with a return value); however, it has the exact same inputs as `Base.sort!`.


Different sorting settings:

```julia

# Automatically uses MPI.COMM_WORLD as communicator; doesn't save sorting stats
sorted_local_array = mpisort!(local_array; alg=SIHSort())

# Reverse sorting; specify communicator explicitly
sorted_local_array = mpisort!(local_array; alg=SIHSort(comm), rev=true)

# Specify key to sort by; see https://docs.julialang.org/en/v1/base/sort/
sorted_local_array = mpisort!(local_array; alg=SIHSort(), by=x->x["key"])

# Different ordering; see https://docs.julialang.org/en/v1/base/sort/#Alternate-orderings
sorted_local_array = mpisort!(local_array; alg=SIHSort(), order=Reverse)

# Save sorting stats
alg = SIHSort(comm)
sorted_local_array = mpisort!(local_array; alg=alg)

@show alg.stats.splitters               # `nranks - 1` elements splitting arrays between nodes
@show alg.stats.num_elements            # `nranks` integers specifying number of elements on each node

# Use different in-place local sorter
alg = SIHSort(comm, nothing)            # Default: standard Base.sort!
alg = SIHSort(comm, QuickSort)          # Specify algorithm, passed to Base.sort!(...; alg=<Algorithm>)
alg = SIHSort(comm, v -> mysorter!(v))  # Pass any function that sorts a local vector in-place

```


### Communication and Memory Footprint

Only optimised collective MPI communication is used, in order: Gather, Bcast, Reduce, Bcast,
Alltoall, Allreduce, Alltoallv. I am not aware of a non-IO based algorithm with less communication
(if you do know one, please open an issue!).

If $N$ is the total number of elements spread out across $P$ MPI ranks, then the per-rank memory
footprint of `SIHSort` is:

$$ k P + k P + P + 3(P - 1) + \frac{N + \epsilon}{P} $$

Where $k$ is the number of samples extracted from each node; following [1], we use:

$$ k = 2P \ log_2 P $$

Except for the final redistribution on a single new array of length $\frac{N + \epsilon}{P}$, the
memory footprint only depends on the number of nodes involved, hence it should be scalable to
thousands of MPI ranks. Anyone got a spare 200,000 nodes to benchmark this?


### Note on sorting multi-node GPU arrays

`SIHSort` is generic over the input array type, so it can work with GPU arrays - e.g. Julia
`CUDA.CuArray` - and benefit from MPI-configured, optimised inter-GPU connects.

However, to be fully performant, it needs:
- A single-node `sort` implementation - at the moment, only `CUDA.CuArray` has one; there is great potential in a `KernelAbstractions.jl` sorter, we really need one!
- A fully GPU-based `searchsortedlast` implementation; **we do not have one** yet, so we rely on a binary search where each tested element is copied to the CPU (!), which of course is not great. More great potential in some optimised `KernelAbstractions.jl` kernels!

While it works currently, it is not ideal: sorting 1,000,000 `Int32` values split across 2 MPI
ranks takes \~0.015s on my Intel i9 CPU and \~0.034s on my NVidia Quadro RTX4000 with Max-Q.


### References

This algorithm builds on prior art:

- [1] _Harsh V, Kale L, Solomonik E. Histogram sort with sampling._ : followed main ideas and theoretical results, but with deterministic sampling and original communication and interpolation optimisations.
- [2] _Sundar H, Malhotra D, Biros G. Hyksort: a new variant of hypercube quicksort on distributed memory architectures._
- [3] _Shi H, Schaeffer J. Parallel sorting by regular sampling._
- [4] _Solomonik E, Kale LV. Highly scalable parallel sorting._
- [5] _John Lapeyre, integer base-2 logarithm_ - https://github.com/jlapeyre/ILog2.jl.
- [6] _Byrne S, Wilcox LC, Churavy V. MPI. jl: Julia bindings for the Message Passing Interface._ : absolute heroes who made MPI a joy to use in Julia.


# License

`MPISort.jl` is MIT-licensed. Enjoy.
