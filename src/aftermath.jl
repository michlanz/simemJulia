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






## function plot_paretocap_from_caps()
##     base = "output3"
##     if !isdir(base)
##         println("Directory 'output3' non trovata.")
##         return
##     end
## 
##     # parametri
##     CROWDLIMIT = 8
## 
##     entries = readdir(base)
##     caps = sort(filter(d -> isdir(joinpath(base, d)) && startswith(d, "cap_"), entries))
##     if isempty(caps)
##         println("Nessuna directory cap_* trovata in 'output3'.")
##         return
##     end
## 
##     cap_ids = Int[]
##     overcrowd_vals = Float64[]           # valore per cap (mediana o fallback calcolato)
##     time_p10 = Float64[]
##     time_med = Float64[]
##     time_p90 = Float64[]
## 
##     for cap in caps
##         # estrai numero cap_XX (fallback: ultima parte dopo '_')
##         m = match(r"cap_(\d+)$", cap)
##         capval = m === nothing ? tryparse(Int, split(cap, "_")[end]) : parse(Int, m.captures[1])
##         if capval === nothing
##             continue
##         end
##         push!(cap_ids, capval)
## 
##         # --- overcrowd: preferisci wip.csv (mediana colonna overcrowd), fallback calcolo da queuelen_box + infoview ---
##         wipfile = joinpath(base, cap, "wip.csv")
##         val_over = NaN
##         if isfile(wipfile)
##             dfw = CSV.read(wipfile, DataFrame)
##             col_over = findfirst(name -> occursin("overcrowd", lowercase(String(name))), names(dfw))
##             if col_over !== nothing
##                 col = skipmissing(dfw[!, names(dfw)[col_over]])
##                 if !isempty(col)
##                     val_over = median(collect(Float64.(col)))
##                 end
##             end
##         end
## 
##         if isnan(val_over)
##             # fallback: se esiste queuelen_box e infoview, calcolo overcrowd = sum(max(q-CROWDLIMIT,0)*total_duration)/simtime
##             qfile = joinpath(base, cap, "queuelen_box.csv")
##             infofile = joinpath(base, cap, "infoview.csv")
##             if isfile(qfile) && isfile(infofile)
##                 try
##                     dfq = CSV.read(qfile, DataFrame)
##                     dfi = CSV.read(infofile, DataFrame)
##                     # prendi il valore "Simulation Time" dalla colonna Median se presente, altrimenti Mean
##                     idx = findfirst(r -> occursin("simulation time", lowercase(String(r))), dfi.KPI)
##                     simtime = nothing
##                     if idx !== nothing
##                         simtime = tryparse(Float64, string(dfi[idx, :Median]))
##                         if simtime === nothing
##                             simtime = tryparse(Float64, string(dfi[idx, :Mean]))
##                         end
##                     end
##                     if simtime !== nothing
##                         # assicurati colonne presenti
##                         if (:queue_length ∈ names(dfq) && :total_duration ∈ names(dfq))
##                             arr = max.(0, dfq.queue_length .- CROWDLIMIT) .* dfq.total_duration
##                             val_over = sum(arr) / Float64(simtime)
##                         end
##                     end
##                 catch
##                     val_over = NaN
##                 end
##             end
##         end
## 
##         push!(overcrowd_vals, val_over)
## 
##         # --- simulation time percentili (infoview) ---
##         infofile = joinpath(base, cap, "infoview.csv")
##         if isfile(infofile)
##             dfi = CSV.read(infofile, DataFrame)
##             idx = findfirst(r -> occursin("simulation time", lowercase(String(r))), dfi.KPI)
##             if idx === nothing
##                 push!(time_p10, NaN); push!(time_med, NaN); push!(time_p90, NaN)
##             else
##                 p10_val = tryparse(Float64, string(dfi[idx, :Percentile10])); p10_val = p10_val === nothing ? NaN : p10_val
##                 med_val = tryparse(Float64, string(dfi[idx, :Median])); med_val = med_val === nothing ? NaN : med_val
##                 p90_val = tryparse(Float64, string(dfi[idx, :Percentile90])); p90_val = p90_val === nothing ? NaN : p90_val
##                 push!(time_p10, p10_val); push!(time_med, med_val); push!(time_p90, p90_val)
##             end
##         else
##             push!(time_p10, NaN); push!(time_med, NaN); push!(time_p90, NaN)
##         end
##     end
## 
##     if isempty(cap_ids)
##         println("Nessun cap valido trovato.")
##         return
##     end
## 
##     # ordino per cap id e filtro NaN coerentemente per i plot
##     order = sortperm(cap_ids)
##     caps_sorted = cap_ids[order]
##     overcrowd_sorted = overcrowd_vals[order]
##     time_p10_sorted = time_p10[order]
##     time_med_sorted = time_med[order]
##     time_p90_sorted = time_p90[order]
## 
##     # --- PLOT overcrowd vs cap (mediana per cap) ---
##     # filtro coppie valide (non NaN) prima del plot
##     valid_idx = findall(!isnan, overcrowd_sorted)
##     if !isempty(valid_idx)
##         xs = caps_sorted[valid_idx]; ys = overcrowd_sorted[valid_idx]
##         p1 = plot(xs, ys, seriestype = :scatter, markerstrokewidth = 0, markersize = 6,
##                   xlabel = "capqueue (cap_n)", ylabel = "Median overcrowd",
##                   title = "Median overcrowd vs capqueue", legend = false)
##         plot!(p1, xs, ys, seriestype = :line)
##         savefig(joinpath(base, "0_paretocap.png"))
##         println("Salvato: ", joinpath(base, "0_paretocap.png"))
##     else
##         println("Nessun valore overcrowd valido per creare 0_paretocap.png")
##     end
## 
##     # --- PLOT simulation time percentiles per cap (P10, Median, P90) ---
##     valid_time_idx = findall(!isnan, time_med_sorted)
##     if !isempty(valid_time_idx)
##         xs = caps_sorted[valid_time_idx]
##         p2 = plot(xs, time_med_sorted[valid_time_idx], label = "Median", linewidth = 2,
##                   xlabel = "capqueue (cap_n)", ylabel = "Simulation time", title = "Simulation time percentiles per cap")
##         plot!(p2, xs, time_p10_sorted[valid_time_idx], label = "P10", linestyle = :dash)
##         plot!(p2, xs, time_p90_sorted[valid_time_idx], label = "P90", linestyle = :dashdot)
##         savefig(joinpath(base, "0_paretotime.png"))
##         println("Salvato: ", joinpath(base, "0_paretotime.png"))
##     else
##         println("Nessun valore tempo di simulazione valido per creare 0_paretotime.png")
##     end
## end
## 
## 
## plot_paretocap_from_caps()









#monitor_df = CSV.read(joinpath(outpath, "monitor.csv"), DataFrame)
#show(filter(row -> occursin("3", row.place), monitor_df), allrows=true)
println()