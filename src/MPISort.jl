module MPISort


# Private imports
using Base.Sort
using Base.Order

using Parameters
using LoopVectorization

import MPI


# Method additions
# import Base.Sort: sort!


# Public exports
export SIHSort, SIHSortStats, sihsort!





"""
    SIHSortStats([splitters], [num_elements])

Useful stats saved after sorting.
"""
@with_kw mutable struct SIHSortStats
    "Values used to split elements across MPI ranks, length=`nranks - 1`"
    splitters::Union{Nothing, Vector}           = nothing

    "Number of elements saved locally to each MPI rank, length=`nranks`."
    num_elements::Union{Nothing, Vector{Int64}} = nothing
end


"""
    SIHSort([comm], [sorter], [stats])

Sampling with interpolated histograms sorting algorithm, or SIHSort (pronounce _sigh_ sort).
"""
@with_kw struct SIHSort <: Algorithm
    "MPI communicator used; by default `MPI.COMM_WORLD`."
    comm::MPI.Comm                              = MPI.COMM_WORLD

    "Local in-place sorter used."
    sorter::Union{Nothing, Algorithm, Function} = nothing

    "Useful stats saved after sorting, e.g. elements' partitioning."
    stats::SIHSortStats                         = SIHSortStats()
end

SIHSort(comm) = SIHSort(;comm=comm)
SIHSort(comm, sorter) = SIHSort(;comm=comm, sorter=sorter)





"""
    sort!

Standard Julia sorting API for SIHSort.

Important: the input vector will be mutated, but the sorted elements for each MPI rank **will be
returned**; this is required as the vector size will change with data migration.
"""
function sihsort!(
    v::AbstractVector;
    alg::SIHSort,
    lt=isless,
    by=identity,
    rev::Bool=false,
    order::Ordering=Forward,
)

    # Error checks
    length(v) > 0 || throw(ArgumentError("`v` must have >= 1 elements"))

    # Extract relevant settings
    comm = alg.comm
    rank = MPI.Comm_rank(comm)
    nranks = MPI.Comm_size(comm)

    if isnothing(alg.sorter)
        sorter! = v -> Base.sort!(v; lt=lt, by=by, rev=rev, order=order)
    elseif alg.sorter isa Algorithm
        sorter! = v -> Base.sort!(v; alg=alg.sorter, lt=lt, by=by, rev=rev, order=order)
    elseif alg.sorter isa Function
        sorter! = alg.sorter
    end

    # Sort local array
    sorter!(v)

    # Trivial case: single MPI rank
    if nranks == 1
        return v
    end

    # Extract samples
    num_elements = length(v)
    num_samples = 2 * nranks * ilog2(nranks, RoundUp)
    num_samples_global = num_samples * nranks
    isamples = IntLinSpace(1, num_elements, num_samples)

    # Figure out key type, then allocate vector of samples
    vtype = typeof(by(v[1]))

    # Allocate vector of samples across all processes; initially only set the
    # first `num_samples` elements
    samples = Vector{vtype}(undef, num_samples_global)

    @inbounds Threads.@threads for i in 1:num_samples
        samples[i] = by(v[isamples[i]])
    end

    # Gather all samples on root process
    if rank == 0
        MPI.Gather!(MPI.IN_PLACE, MPI.UBuffer(samples, num_samples), 0, comm)
    else
        MPI.Gather!(MPI.Buffer(@view(samples[1:num_samples])), nothing, 0, comm)
    end

    # Sort gathered samples on root process
    if rank == 0
        sorter!(samples)
    end

    # Broadcast sorted samples to all processes
    MPI.Bcast!(samples, 0, comm)

    # Compute histograms for each sample - i.e. find number of elements before them.
    # Optimisation: add one extra element at the end equal to the number of
    # elements across all processes; reduces number of communications
    histogram = Vector{Int64}(undef, num_samples_global + 1)
    histogram[end] = num_elements

    @inbounds Threads.@threads for i in 1:num_samples_global
        # TODO: check the `by` is only applied on `v`
        histogram[i] = searchsortedlast(v, samples[i]; by=by, lt=lt, rev=rev, order=order)
    end

    # Sum all histograms on root to find samples' _global_ positions.
    MPI.Reduce!(histogram, +, 0, comm)

    # Optimisation: the last element was the number of elements across all
    # processes (only on root, after the reduction). Extract it, then delete it
    num_elements_global = histogram[end]
    histogram = @view(histogram[1:end - 1])

    # Select best splitters on root process
    num_splitters = nranks - 1
    splitters = Vector{vtype}(undef, num_splitters)

    if rank == 0
        @inbounds Threads.@threads for i in 1:num_splitters
            # Best splitter divides all elements equally across processes
            ideal_position = div(i * num_elements_global, nranks, RoundNearest)
            closest_index = searchsortedlast(histogram, ideal_position)

            # If the keys / samples are numbers, interpolate to find better splitter
            if vtype <: Number
               # Linear function from (x0, y0) to (x1, y1), where x is the sample
               # and y is the histogram / global position
                if closest_index == num_samples_global
                    splitters[i] = samples[closest_index]
                    continue
                end

                x0 = samples[closest_index]
                x1 = samples[closest_index + 1]

                y0 = histogram[closest_index]
                y1 = histogram[closest_index + 1]

                ideal_splitter = x0 + (ideal_position - y0) / (y1 - y0) * (x1 - x0)

                if vtype <: Integer
                    splitters[i] = ceil(ideal_splitter)
                else
                    splitters[i] = ideal_splitter
                end

            # Otherwise use the sample directly as a splitter
            else
                splitters[i] = samples[closest_index]
            end
        end
    end

    # Broadcast best splitters on all processes
    MPI.Bcast!(splitters, 0, comm)

    # Histogram splitters; reuse previous histogram variable, which is always larger.
    # Same optimisation as above - save one extra element as the total number of
    # elements being sorted
    histogram = @view(histogram[1:num_splitters + 1])

    if rank == 0
        histogram[end] = num_elements_global
    else
        histogram[end] = 0                      # Will be reduced
    end

    @inbounds Threads.@threads for i in 1:num_splitters
        histogram[i] = searchsortedlast(v, splitters[i]; by=by, lt=lt, rev=rev, order=order)
    end

    # The histogram dictates how many elements will be sent to each process
    num_elements_send = Vector{Int64}(undef, nranks)
    num_elements_send[1] = histogram[1]
    @turbo for i in 2:nranks - 1
        num_elements_send[i] = histogram[i] - histogram[i - 1]
    end
    num_elements_send[nranks] = num_elements - histogram[nranks - 1]

    # Inform each process of number of elements to be received
    num_elements_recv = Vector{Int64}(undef, nranks)

    MPI.Alltoall!(
        MPI.UBuffer(num_elements_send, 1),
        MPI.UBuffer(num_elements_recv, 1),
        comm
    )

    # Summing the histogram will dictate how many elements will be stored locally.
    # Allreduce makes the reduction result available on all processes
    MPI.Allreduce!(histogram, +, comm)

    # Same optimisation as above, the last element was the global number of items 
    # to sort. Extract it, then delete it
    num_elements_global = histogram[end]
    histogram = @view(histogram[1:num_splitters])

    # Compute number of elements to be stored on each process
    num_elements_after = Vector{Int64}(undef, nranks)

    num_elements_after[1] = histogram[1]
    @turbo for i in 2:nranks - 1
        num_elements_after[i] = histogram[i] - histogram[i - 1]
    end
    num_elements_after[nranks] = num_elements_global - histogram[nranks - 1]

    # Pre-allocate array to receive elements from the other processes
    vafter = similar(v, num_elements_after[rank + 1])

    MPI.Alltoallv!(
        MPI.VBuffer(v, num_elements_send),
        MPI.VBuffer(vafter, num_elements_recv),
        comm,
    )

    # Final local sort
    sorter!(vafter)

    # Save sorting stats
    alg.stats.splitters = splitters
    alg.stats.num_elements = num_elements_after

    vafter
end




# Create an integer linear space between start and stop on demand
struct IntLinSpace{T <: Integer}
    start::T
    stop::T
    length::T
end


function IntLinSpace(start::Integer, stop::Integer, length::Integer)
    start <= stop || throw(ArgumentError("`start` must be <= `stop`"))
    length >= 2 || throw(ArgumentError("`length` must be >= 2"))

    IntLinSpace{typeof(start)}(start, stop, length)
end


Base.IndexStyle(::IntLinSpace) = IndexLinear()
Base.length(ils::IntLinSpace) = ils.length

Base.firstindex(::IntLinSpace) = 1
Base.lastindex(ils::IntLinSpace) = ils.length

function Base.getindex(ils::IntLinSpace, i)
    @boundscheck 1 <= i <= ils.length || throw(BoundsError(ils, i))

    if i == 1
        ils.start
    elseif i == length
        ils.stop
    else
        ils.start + div((i - 1) * (ils.stop - ils.start), ils.length - 1, RoundUp)
    end
end


# Fast integer log2 taken from https://github.com/jlapeyre/ILog2.jl to
# minimise number of dependencies. Thank you for this implementation!
const IntBits  = Union{Int8, Int16, Int32, Int64, Int128,
                       UInt8, UInt16, UInt32, UInt64, UInt128}

ilog2(x, ::typeof(RoundUp)) = ispow2(x) ? ilog2(x) : ilog2(x) + 1
ilog2(x, ::typeof(RoundDown)) = ilog2(x)

@generated function msbindex(::Type{T}) where {T<:Integer}
    return sizeof(T) * 8 - 1
end

function ilog2(n::T) where {T<:IntBits}
    n > zero(T) || throw(DomainError(n))
    msbindex(T) - leading_zeros(n)
end


end
