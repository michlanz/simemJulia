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
include("./simemJulia.jl")

using .simemJulia
using .showdash
using .structures

savefigs()






function plot_paretocap_from_caps()
    base = "output3"
    if !isdir(base)
        println("Directory 'output3' non trovata.")
        return
    end

    entries = readdir(base)
    caps = filter(d -> isdir(joinpath(base, d)) && startswith(d, "cap_"), entries)
    if isempty(caps)
        println("Nessuna directory cap_* trovata in 'output3'.")
        return
    end

    rows = Tuple{Int,Float64}[]
    for cap in caps
        m = match(r"cap_(\d+)", cap)
        capval = m === nothing ? tryparse(Int, split(cap, "_")[end]) : parse(Int, m.captures[1])
        p = joinpath(base, cap, "wip.csv")
        if !isfile(p)
            continue
        end
        df = CSV.read(p, DataFrame)
        col = findfirst(name -> occursin("overcrowd", lowercase(String(name))), names(df))
        if col === nothing
            continue
        end
        push!(rows, (capval, median(df[!, names(df)[col]])))
    end

    if isempty(rows)
        println("Nessun valore di overcrowd trovato in 'output3/cap_*'.")
        return
    end

    sort!(rows, by = x -> x[1])
    caps_sorted = first.(rows)
    medians = last.(rows)

    p = plot(caps_sorted, medians,
        seriestype = :scatter,
        markerstrokewidth = 0,
        markersize = 6,
        xlabel = "capqueue (cap_n)",
        ylabel = "Median overcrowd",
        title = "Median overcrowd vs capqueue",
        legend = false)
    plot!(caps_sorted, medians, seriestype = :line)

    outpng = joinpath(base, "0_paretocap.png")
    savefig(p, outpng)
    println("Salvato: ", outpng)
end
# chiamata
plot_paretocap_from_caps()









#monitor_df = CSV.read(joinpath(outpath, "monitor.csv"), DataFrame)
#show(filter(row -> occursin("3", row.place), monitor_df), allrows=true)
println()