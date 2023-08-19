using MPISort
using Documenter

makedocs(
    modules = [MPISort],
    sitename = "MPISort.jl",
    format = Documenter.HTML(
        # Only create web pretty-URLs on the CI
        prettyurls = get(ENV, "CI", nothing) == "true",
    ),
)
deploydocs(repo = "github.com/anicusan/MPISort.jl.git")
