println("eccoci qui, follettini e follettine")
using DataFrames
using StatsPlots
using Plots
using CSV
using Distributions
using ConcurrentSim

include("./structures.jl")
include("./output.jl")

using .showdash
using .structures

outpath = "output"
plotresults(outpath)
println("grafici fatti")