println("eccoci qui, follettini e follettine")
using DataFrames
using StatsPlots
using Plots
using CSV
using Distributions
using ConcurrentSim
using StableRNGs

include("./structures.jl")
include("./output.jl")

using .showdash
using .structures

outpath = "output2"
plotresults(outpath)
println("grafici fatti")


#monitor_df = CSV.read(joinpath(outpath, "monitor.csv"), DataFrame)
#show(filter(row -> occursin("3", row.place), monitor_df), allrows=true)
println()