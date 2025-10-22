println("eccoci qui, follettini e follettine")
using DataFrames
using StatsPlots
using Plots
using CSV
using Distributions
using ConcurrentSim
using StableRNGs
using Statistics
using PrettyTables

include("./structures.jl")
include("./output.jl")
include("./simemjulia.jl")

using .simemJulia
using .showdash
using .structures

savefigs()


#monitor_df = CSV.read(joinpath(outpath, "monitor.csv"), DataFrame)
#show(filter(row -> occursin("3", row.place), monitor_df), allrows=true)
println()