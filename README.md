# MPISort
_Don't put all your eggs in one basket!_

Sorting $N$ elements spread out across $P$ processors, _with no processor being able to hold all elements at once_ is a difficult problem, with few open-source implementations in [C++](https://github.com/hsundar/usort) and [Charm++](https://github.com/vipulharsh/HSS). This library hosts such MPI-based sorting algorithms for the Julia ecosystem; at the moment, one optimised algorithm is provided:


## `SIHSort`

Sampling with interpolated histograms sorting algorithm (pronounced _sigh_ sort, like anything
MPI-related), optimised for minimum inter-rank communication and memory footprint. Features:

- **Does not require that distributed data fits into the memory of a single node**. No IO either.
- Works for any comparison-based data, with additional optimisations for numeric elements.
- Optimised for minimum MPI communication; can use Julia threads on each shared-memory node.
- The node-local arrays may have different sizes; sorting will try to balance number of elements held by each MPI rank.
- Works with any `AbstractVector`, including accelerators such as GPUs (TODO: test this further). Julia type-inference and optimisations do wonders.
- Implements the standard Julia `sort!` API, and naturally works for custom data, comparisons, orderings, etc.


### Example

```julia

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
sorted_local_array = sihsort!(local_array; alg=alg)

# Print each local array sequentially
for i in 0:nranks - 1
    rank == i && @show rank sorted_local_array alg.stats
    MPI.Barrier(comm)
end

```


### Communication and Memory Footprint

MPI communication subroutines used, in order: Gather, Bcast, Reduce, Bcast, Alltoall, Allreduce, Alltoallv. I am not aware of a non-IO based algorithm with less communication (if you do know one, please open an issue!).

If $N$ is the total number of elements spread out across $P$ MPI ranks, then `SIHSort` needs, per rank:

$$ k P + k P + P + 3(P - 1) + \sim \frac{N}{P} $$
$$ k = 2P log_2 P $$

Except for the final redistribution on a single new array of length $\sim \frac{N}{P}$, the memory footprint only depends on the number of nodes involved, hence it should be scalable to thousands of MPI ranks. Anyone got a spare 200,000 nodes to benchmark this?


### References

This algorithm, builds strongly on prior art:

- _Harsh V, Kale L, Solomonik E. Histogram sort with sampling._ : followed main ideas and theoretical results, but with deterministic sampling and original communication and interpolation optimisations.
- _Sundar H, Malhotra D, Biros G. Hyksort: a new variant of hypercube quicksort on distributed memory architectures._
- _Shi H, Schaeffer J. Parallel sorting by regular sampling._
- _Solomonik E, Kale LV. Highly scalable parallel sorting._
- _John Lapeyre, integer base-2 logarithm_ - https://github.com/jlapeyre/ILog2.jl.
- _Byrne S, Wilcox LC, Churavy V. MPI. jl: Julia bindings for the Message Passing Interface._ : absolute heroes who made MPI a joy to use in Julia.


# License

`MPISort.jl` is MIT-licensed. Enjoy.
