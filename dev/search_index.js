var documenterSearchIndex = {"docs":
[{"location":"#MPISort.jl-Documentation","page":"MPISort.jl Documentation","title":"MPISort.jl Documentation","text":"","category":"section"},{"location":"","page":"MPISort.jl Documentation","title":"MPISort.jl Documentation","text":"Distributed MPI-based sorting API with the same inputs as the base Julia sorters.","category":"page"},{"location":"#Index","page":"MPISort.jl Documentation","title":"Index","text":"","category":"section"},{"location":"","page":"MPISort.jl Documentation","title":"MPISort.jl Documentation","text":"","category":"page"},{"location":"sihsort/#SIHSort-API","page":"SIHSort API","title":"SIHSort API","text":"","category":"section"},{"location":"sihsort/","page":"SIHSort API","title":"SIHSort API","text":"Sampling with interpolated histograms sorting algorithm, or SIHSort (pronounce sigh sort).","category":"page"},{"location":"sihsort/","page":"SIHSort API","title":"SIHSort API","text":"mpisort!\nSIHSort\nSIHSortStats","category":"page"},{"location":"sihsort/#MPISort.mpisort!","page":"SIHSort API","title":"MPISort.mpisort!","text":"function mpisort!(\n    v::AbstractVector;\n    alg::SIHSort,\n    lt=isless,\n    by=identity,\n    rev::Bool=false,\n    order::Ordering=Forward,\n)\n\nDistributed MPI-based sorting API with the same inputs as the base Julia sorters.\n\nImportant: the input vector will be mutated, but the sorted elements for each MPI rank will be returned; this is required as the vector size will change with data migration.\n\n\n\n\n\n","category":"function"},{"location":"sihsort/#MPISort.SIHSort","page":"SIHSort API","title":"MPISort.SIHSort","text":"struct SIHSort <: Base.Sort.Algorithm\n\nSampling with interpolated histograms sorting algorithm, or SIHSort (pronounce sigh sort).\n\nMethods\n\nSIHSort(comm)\nSIHSort(comm, sorter)\nSIHSort(;comm=MPI.COMM_WORLD, sorter=nothing, stats=SIHSortStats())\n\nFields\n\ncomm::MPI.Comm\n\n: MPI communicator used. Default: MPI.COMM_WORLD\n\nsorter::Union{Nothing, Function, Base.Sort.Algorithm}\n\n: Local in-place sorter used. Default: nothing\n\nstats::SIHSortStats\n\n: Useful stats saved after sorting, e.g. elements' partitioning. Default: SIHSortStats()\n\n\n\n\n\n","category":"type"},{"location":"sihsort/#MPISort.SIHSortStats","page":"SIHSort API","title":"MPISort.SIHSortStats","text":"mutable struct SIHSortStats\n\nUseful stats saved after sorting.\n\nMethods\n\nSIHSortStats(splitters, num_elements)\nSIHSortStats(;splitters=nothing, num_elements=nothing)\n\nFields\n\nsplitters::Union{Nothing, Vector}\n\n: Values used to split elements across MPI ranks, length=nranks - 1 Default: nothing\n\nnum_elements::Union{Nothing, Vector{Int64}}\n\n: Number of elements saved locally to each MPI rank, length=nranks. Default: nothing\n\n\n\n\n\n","category":"type"}]
}