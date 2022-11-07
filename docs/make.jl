using MPISort
using Documenter

makedocs(modules = [MPISort], sitename = "MPISort.jl")

deploydocs(repo = "github.com/anicusan/MPISort.jl.git")
