module postprocess

using ..CSV
using ..DataFrames
#using ..DataFrames: names
using ..Statistics
using ..DataFrames: sort!
using ..structures: Dash, SystemLog, ProcessingTimeLog, QueueLenLog, QueueTimeLog, UnitsInSystemLog, MakespanLog, Station, Client

export postprocessDF,
       buildQueuelenbox,
       buildSaturation

# TODO buttaci dentro anche l'integrale di stocazzo sai magari con il cap e salva pure lui.
# todo magari un vettore results o salvo in loco alla fine. esce funz lunghina ma sticazzi
# tanto questo lo dovrò rifare sempre duh non lo so vedrò
# memo che non l'hai ancora testato e puoi abbattere i writecsv onestamente (basta salvarli puri)

function postprocessDF(dashvector::Vector{Dash}, CLIENTNUM::Int64)
    CROWDLIMIT::Int64 = 5
    MINQ::Float64 = 0.1
    MAXQ::Float64 = 0.9

    vector_simtime::Vector{Float64} = Float64[]
    vector_overcrowd::Vector{Float64} = Float64[]
    vector_mean_makespan::Vector{Float64} = Float64[]
    vector_mean_saturation::Vector{Float64} = Float64[]
    vector_mean_queuetime::Vector{Float64} = Float64[]
    
    merged_queuelenbox::DataFrame = DataFrame()
    merged_queuetimebox::DataFrame = DataFrame()
    merged_makespanbox::DataFrame = DataFrame()
    concat_saturation::DataFrame = DataFrame()
    

    for dash in dashvector
        simtime = dash.monitor_log[end].timestamp
        append!(vector_simtime, simtime)

        df_queuelenbox = buildQueuelenbox(DataFrame(dash.queue_len_log), simtime)
        append!(merged_queuelenbox, df_queuelenbox)

        df_queuetimebox = sort!(DataFrame(dash.queue_time_log), [:station])
        append!(merged_queuetimebox, df_queuetimebox)
        push!(vector_mean_queuetime, sum(df_queuetimebox.waiting_time) / CLIENTNUM)

        df_makespanbox = sort!(DataFrame(dash.makespan_log), [:client_code])
        append!(merged_makespanbox, df_makespanbox)
        push!(vector_mean_makespan, mean(df_makespanbox.makespan)) # <-- RIGA DA AGGIUNGERE

        df_saturation = buildSaturation(DataFrame(dash.processing_times_log), simtime)
        append!(concat_saturation, df_saturation)
        push!(vector_mean_saturation, mean(df_saturation.processing_percent)) # <-- RIGA DA AGGIUNGERE

        #TODO farei diviso per tempo e diviso per stazioni, per dare un'idea effettiva
        df_overcrowd = filter(row -> row.queue_length > CROWDLIMIT, df_queuelenbox)
        if !isempty(df_overcrowd)
            overcrowd = sum((df_overcrowd.queue_length .- CROWDLIMIT) .* df_overcrowd.total_duration) / simtime
            push!(vector_overcrowd, overcrowd)
        else
            push!(vector_overcrowd, 0.0) 
        end

    end
    # ----------------- 
    df_simtime = DataFrame(simtime = vector_simtime)
    merged_saturation = combine(groupby(concat_saturation, :machine), DataFrames.names(concat_saturation, Number) .=> mean; renamecols=false)
    df_overcrowd_results = DataFrame(overcrowd_value = vector_overcrowd)
    
    # ----------- qui il df infoview messo dentro per semplicita
    df_infoview = DataFrame(KPI=String[], Mean=Float64[], StdDevAmongSimulations=Float64[], Percentile10=Float64[], Median=Float64[], Percentile90=Float64[])
    push!(df_infoview, ("Replications", length(dashvector), NaN, NaN, NaN, NaN))
    push!(df_infoview, ("Lots per Run", CLIENTNUM, NaN, NaN, NaN, NaN)) # CLIENTNUM deve essere accessibile
    push!(df_infoview, ("Overcrowd (units)", mean(vector_overcrowd), std(vector_overcrowd), quantile(vector_overcrowd, MINQ), median(vector_overcrowd), quantile(vector_overcrowd, MAXQ)))
    push!(df_infoview, ("Simulation Time", mean(df_simtime.simtime), std(df_simtime.simtime), quantile(df_simtime.simtime, MINQ), median(df_simtime.simtime), quantile(df_simtime.simtime, MAXQ)))
    push!(df_infoview, ("Machine Saturation (%)", mean(vector_mean_saturation), std(vector_mean_saturation), quantile(vector_mean_saturation, MINQ), median(vector_mean_saturation), quantile(vector_mean_saturation, MAXQ)))
    push!(df_infoview, ("Lot Makespan", mean(vector_mean_makespan), std(vector_mean_makespan), quantile(vector_mean_makespan, MINQ), median(vector_mean_makespan), quantile(vector_mean_makespan, MAXQ)))
    push!(df_infoview, ("Lot Total Queue Time", mean(vector_mean_queuetime), std(vector_mean_queuetime), quantile(vector_mean_queuetime, MINQ), median(vector_mean_queuetime), quantile(vector_mean_queuetime, MAXQ)))

    return (
            infoview = df_infoview,
            overcrowd = df_overcrowd_results,
            makespan_box = merged_makespanbox,
            saturation = merged_saturation,
            queuetime_box = merged_queuetimebox,
            queuelen_box = merged_queuelenbox
            )

end

function buildQueuelenbox(df_queuelen::DataFrame, sim_time::Float64)
    sort!(df_queuelen, [:station, :timestamp])

    df_queuelen.duration = zeros(nrow(df_queuelen))

    for station_group in groupby(df_queuelen, :station)
        filtering = df_queuelen.station .== first(station_group.station)
        rows = findall(filtering)
        for i in 1:length(rows)-1
            df_queuelen.duration[rows[i]] = df_queuelen.timestamp[rows[i+1]] - df_queuelen.timestamp[rows[i]]
        end
        df_queuelen.duration[rows[end]] = sim_time - df_queuelen.timestamp[rows[end]]
    end

    df_queuelen = combine(groupby(df_queuelen, [:station, :queue_length]), :duration => sum => :total_duration)
    df_queuelen.percent = 100 .* df_queuelen.total_duration ./ sim_time
    sort!(df_queuelen, [:station, :queue_length])

    return df_queuelen
end
function buildSaturation(df_saturation::DataFrame, sim_time::Float64)
    df_saturation = combine(groupby(df_saturation, :machine), :processing_time => sum => :total_processing_time)
    sort!(df_saturation, :machine)
 
    df_saturation.processing_percent = 100 .* df_saturation.total_processing_time ./ sim_time

    df_saturation.down_percent = zeros(size(df_saturation, 1))    # placeholder
    df_saturation.repair_percent = zeros(size(df_saturation, 1))  # placeholder
    df_saturation.maint_percent = zeros(size(df_saturation, 1))  # placeholder

    df_saturation.idle_percent = 100 .- df_saturation.processing_percent .- df_saturation.down_percent .- df_saturation.repair_percent .-df_saturation.maint_percent

    return df_saturation
end

function nonvogliocancellareicommenti()
    ## # ### in pausa tutto qui perchP elaboravo e salvavo insieme
    ## # # ===================================================================================================================================================
    ## # 
    ## # 
    ## #     #NOTE decidi se i clienti stanno dentro o fuori. io ho deciso fuori e quindi li ho levati in toto
    ## # function postprocessCSV(dash::Dash, outpath::String)
    ## #     println("##### ci apprestiamo a salvare i dati ######")
    ## #     mkpath(outpath)
    ## #     writecsvMonitor(dash.monitor_log, outpath)
    ## #     writecsvSaturation(dash.processing_times_log, outpath, dash.monitor_log[end].timestamp)
    ## #     writecsvQueuelen(dash.queue_len_log, outpath, dash.monitor_log[end].timestamp)
    ## #     writecsvQueuetime(dash.queue_time_log, outpath)
    ## #     writecsvUnitsinsystem(dash.units_in_system_log, outpath)
    ## #     writecsvMakespan(dash.makespan_log, outpath)
    ## #     println("##### salvataggio dei dati avvenuto ########")
    ## #     println()
    ## #     #CSV.write(joinpath(outpath, "clients.csv"), DataFrame(id = getfield.(clients, :id), code = getfield.(clients, :code), priority = getfield.(clients, :priority)))
    ## # end
    ## # 
    ## # 
    ## # function writecsvMonitor(logs::Vector{SystemLog}, outpath::String)
    ## #     df_monitor = DataFrame(logs)
    ## #     sort!(df_monitor, :timestamp)
    ## #     CSV.write(joinpath(outpath, "monitor.csv"), df_monitor)
    ## # end
    ## # 
    ## # function writecsvSaturation(logs::Vector{ProcessingTimeLog}, outpath::String, sim_time::Float64)
    ## #     df_saturation = combine(groupby(DataFrame(logs), :machine), :processing_time => sum => :total_processing_time)
    ## #     sort!(df_saturation, :machine)
    ## #  
    ## #     df_saturation.processing_percent = 100 .* df_saturation.total_processing_time ./ sim_time
    ## # 
    ## #     df_saturation.down_percent = zeros(size(df_saturation, 1))    # placeholder
    ## #     df_saturation.repair_percent = zeros(size(df_saturation, 1))  # placeholder
    ## #     df_saturation.maint_percent = zeros(size(df_saturation, 1))  # placeholder
    ## # 
    ## #     df_saturation.idle_percent = 100 .- df_saturation.processing_percent .- df_saturation.down_percent .- df_saturation.repair_percent .-df_saturation.maint_percent
    ## #  
    ## #     CSV.write(joinpath(outpath, "saturation.csv"), df_saturation)
    ## # end
    ## # 
    ## # function writecsvQueuelen(logs::Vector{QueueLenLog}, outpath::String, sim_time::Float64)
    ## #     df_queuelen = DataFrame(logs)
    ## #     sort!(df_queuelen, [:station, :timestamp])
    ## #     CSV.write(joinpath(outpath, "queuelen_time.csv"), df_queuelen)
    ## # 
    ## #     df_queuelen.duration = zeros(nrow(df_queuelen))
    ## # 
    ## #     for station_group in groupby(df_queuelen, :station)
    ## #         filtering = df_queuelen.station .== first(station_group.station)
    ## #         rows = findall(filtering)
    ## #         for i in 1:length(rows)-1
    ## #             df_queuelen.duration[rows[i]] = df_queuelen.timestamp[rows[i+1]] - df_queuelen.timestamp[rows[i]]
    ## #         end
    ## #         df_queuelen.duration[rows[end]] = sim_time - df_queuelen.timestamp[rows[end]]
    ## #     end
    ## # 
    ## #     df_queuelen = combine(groupby(df_queuelen, [:station, :queue_length]), :duration => sum => :total_duration)
    ## #     df_queuelen.percent = 100 .* df_queuelen.total_duration ./ sim_time
    ## #     sort!(df_queuelen, [:station, :queue_length])
    ## # 
    ## #     open(joinpath(outpath, "queuelen_box.csv"), "w") do file
    ## #         println(file, "station,queue_length")
    ## #         for row in eachrow(df_queuelen)
    ## #             for _ in 1:Int(round(row.percent))
    ## #                 println(file, "$(row.station),$(row.queue_length)")
    ## #             end
    ## #         end
    ## #     end
    ## # end
    ## # 
    ## # 
    ## # function writecsvQueuetime(logs::Vector{QueueTimeLog}, outpath::String)
    ## #     df_queuetime = DataFrame(logs)
    ## #     sort!(df_queuetime, [:station])
    ## #     CSV.write(joinpath(outpath, "queuetime_box.csv"), df_queuetime)
    ## # end
    ## # 
    ## # function writecsvUnitsinsystem(logs::Vector{UnitsInSystemLog}, outpath::String)
    ## #     df_units = DataFrame(logs)
    ## #     sort!(df_units, [:timestamp])
    ## #     CSV.write(joinpath(outpath, "unitsinsystem_time.csv"), df_units)
    ## # end
    ## # 
    ## # function writecsvMakespan(logs::Vector{MakespanLog}, outpath::String)
    ## #     df_makespan = DataFrame(logs)
    ## #     sort!(df_makespan, [:client_code])
    ## #     CSV.write(joinpath(outpath, "makespan_box.csv"), df_makespan)
    ## # end
end

end


#######################################################################################################################
module showdash

using ..CSV
using ..DataFrames
using ..StatsPlots
using ..Plots
using ..PrettyTables

export plotresults,
       plot_saturation,
       plot_queuelen_box,
       plot_queuetime_box,
       plot_makespan_box,
       plot_infoview,
       plot_overcrowd,
       closingprint
       #plot_clients, plot_unitsinsystem, plot_queuelen_time

       using CSV, DataFrames, Plots


       
function plotresults(outpath::String)#; monitor::Vector{SystemLog}; clients::Vector{Client})    
    println("##### iniziando a plottare i grafici #######")
    p1 = plot_saturation(outpath)
    #p6 = plot_queuelen_time(outpath)
    p3 = plot_queuelen_box(outpath)
    p4 = plot_queuetime_box(outpath)
    #p5 = plot_unitsinsystem(outpath)
    p2 = plot_makespan_box(outpath)
    #plot_gantt(outpath)
    p5 = plot_infoview(outpath)
    p6 = plot_overcrowd(outpath)
    #savefig(Plots.plot(p1, p2, p3, p4, p5, p6; grid=(2, 3), size=(2600, 1400), left_margin=15*Plots.mm, bottom_margin=15*Plots.mm), joinpath(outpath, "dashfig.png"))
    #pie = plot_clients(outpath)

    savefig(Plots.plot(p5, p6, p1, p2, p3, p4; grid=(2, 3), size=(2600, 1400), left_margin=15*Plots.mm, bottom_margin=15*Plots.mm), joinpath(outpath, "dashfig.png"))
    println("##### grafici salvati ######################")
end

function plot_infoview(outpath::String)
    df_infoview = CSV.read(joinpath(outpath, "infoview.csv"), DataFrame)

    df_top = df_infoview[:, ["KPI", "Mean", "StdDevAmongSimulations"]]
    df_bottom = df_infoview[:, ["KPI", "Percentile10", "Median", "Percentile90"]]

    table_str_top = pretty_table(String, df_top;
        header = ["KPI", "Mean", "Dev.Std"],
        header_crayon = crayon"bold yellow",
        formatters = ft_printf("%.2f")
    )
    
    table_str_bottom = pretty_table(String, df_bottom;
        header = ["KPI", "P10", "Median", "P90"],
        header_crayon = crayon"bold yellow",
        formatters = ft_printf("%.2f")
    )

    p = plot(framestyle = :none, legend=false, yticks=[], xticks=[])
    # consolas 
    #fira mono
    #hack

    annotate!(p, -0.10, 0.70, text(table_str_top, :left, 14, "JuliaMono"))
    annotate!(p, -0.10, 0.20, text(table_str_bottom, :left, 14, "JuliaMono"))

    return p
end

function plot_overcrowd(outpath::String)
    df_overcrowd = CSV.read(joinpath(outpath, "overcrowd.csv"), DataFrame)
    sorted_overcrowd = sort(df_overcrowd.overcrowd_value)
    p = plot(sorted_overcrowd, xlabel = "Simulation Run (sorted by outcome)", ylabel = "Overcrowd Value", title = "Overcrowd Distribution", legend = false, linewidth = 2.5)
    return p
end

function plot_saturation(outpath::String)
    df = CSV.read(joinpath(outpath, "saturation.csv"), DataFrame)
    p = groupedbar(
        df.machine,
        [df.idle_percent df.maint_percent df.repair_percent df.down_percent df.processing_percent], xlabel = "Machine", ylabel = "Percent (%)", title = "Resource Usage", label = ["Idle" "Maintenance" "Repair" "Down" "Working"], bar_position = :stack, legend = true, color = [:gray90 :lightskyblue2 :lightgoldenrod1 :tomato2 :palegreen2])
    hline!(p, [100], color=:black, linestyle=:dash, label="100%")
    return p
end

function plot_queuelen_box(outpath::String)
    df = CSV.read(joinpath(outpath, "queuelen_box.csv"), DataFrame)
    p = boxplot( df.station, df.queue_length, xlabel = "WorkStation", ylabel = "Queue Length", title = "Queue Length Distribution per WorkStation")
    return p
end

function plot_queuetime_box(outpath::String)
    df = CSV.read(joinpath(outpath, "queuetime_box.csv"), DataFrame)
    p = boxplot(df.station, df.waiting_time, xlabel = "Machine", ylabel = "Waiting Time", title = "Waiting Time Distribution per WorkStation")
    return p
end

function plot_makespan_box(outpath::String)
    df = CSV.read(joinpath(outpath, "makespan_box.csv"), DataFrame)
    p = boxplot(df.client_code, df.makespan, xlabel = "Client Code", ylabel = "Makespan", title = "Makespan Distribution per Client")
    return p
end




function nonvogliocancellareicommenti2()

    ## # function plot_queuelen_time(outpath::String)
    ## #     df = CSV.read(joinpath(outpath, "queuelen_time.csv"), DataFrame)
    ## #     stations = unique(df.station)
    ## #     plt = Plots.plot(title = "Queue Length Over Time", xlabel = "Time", ylabel = "Queue Length")
    ## #     show_legend = length(stations) < 20
    ## #     for m in stations
    ## #         subdf = df[df.station .== m, :]
    ## #         Plots.plot!(plt, subdf.timestamp, subdf.queue_length, label = show_legend ? m : false, seriestype=:steppost, linewidth = 2.5)
    ## #     end
    ## #     return plt
    ## # end
    ## # 
    ## # function plot_unitsinsystem(outpath::String)
    ## #     df = CSV.read(joinpath(outpath, "unitsinsystem_time.csv"), DataFrame)
    ## #     p = Plots.plot(df.timestamp, df.units_in_system, xlabel = "Time", ylabel = "Units in System", title = "Units in System Over Time", legend = false, seriestype=:steppost, linewidth = 2.5)
    ## #     return p
    ## # end

    # ## function plot_gantt(outpath::String)
    # ##     df = CSV.read(joinpath(outpath, "monitor.csv"), DataFrame)
    # ##     sort!(df, [:place, :timestamp])
    # ## 
    # ##     # intervalli startfinish per ogni macchina
    # ##     intervals = DataFrame(machine=String[], client=Int[], code=String[], start=Float64[], finish=Float64[])
    # ##     for m in unique(df.place)
    # ##         df_m = df[(df.place .== m) .& ((df.event .== "startprocess") .| (df.event .== "finishprocess")), :]
    # ##         i = 1
    # ##         while i <= nrow(df_m) - 1
    # ##             if df_m.event[i] == "startprocess" && df_m.event[i+1] == "finishprocess"
    # ##                 push!(intervals, (m, df_m.id_client[i], df_m.code[i], df_m.timestamp[i], df_m.timestamp[i+1]))
    # ##                 i += 2
    # ##             else
    # ##                 i += 1
    # ##             end
    # ##         end
    # ##     end
    # ## 
    # ##     # ordine clienti per primo ingresso nel sistema
    # ##     arr = df[df.event .== "systemarrival", [:id_client, :timestamp]]
    # ##     clients_order = unique(sort(arr, :timestamp).id_client)
    # ## 
    # ##     # palette e mapping colori (mantengo :cool)
    # ##     base_palette = Plots.palette(:cool, length(clients_order))
    # ##     colors = [base_palette[findfirst(==(r.client), clients_order)] for r in eachrow(intervals)]
    # ## 
    # ##     # dimensioni adattive
    # ##     sim_time = maximum(df.timestamp)
    # ##     machines = unique(intervals.machine)
    # ##     nmachines = length(machines)
    # ##     fig_w = round(37 * sim_time)
    # ##     fig_h = round(70 * nmachines)
    # ##     tfs  = round(2 * nmachines) # title font size
    # ##     gfs  = round(1 * nmachines) # axes labels font size
    # ##     lfs  = round(0.02 * nmachines) # label dentro i box
    # ## 
    # ##     # rettangoli
    # ##     rect(w,h,x,y) = Shape(x .+ [0,w,w,0], y .+ [0,0,h,h])
    # ##     shapes = [rect(r.finish - r.start, 0.8, r.start, findfirst(==(r.machine), machines) - 0.4) for r in eachrow(intervals)]
    # ## 
    # ##     p = plot(shapes, c=permutedims(colors), legend=false,
    # ##              yticks=(1:nmachines, machines),
    # ##              xlabel="Time", ylabel="Machines", title="Client Processing Timeline",
    # ##              size=(fig_w, fig_h),
    # ##              titlefontsize=tfs, guidefontsize=gfs, tickfontsize=gfs)
    # ## 
    # ##     for r in eachrow(intervals)
    # ##         y = findfirst(==(r.machine), machines)
    # ##         annotate!((r.start + r.finish) / 2, y, text("$(r.code).$(r.client)", lfs, :black, :center))
    # ##     end
    # ## 
    # ##     savefig(p, joinpath(outpath, "ganttfig.png"))
    # ##     return p
    # ## end
    # ## 
    # ## 
    # ## function plot_clients(outpath::String)
    # ##     df = CSV.read(joinpath(outpath, "clients.csv"), DataFrame)
    # ##     freq = combine(groupby(df, :code), nrow => :count)
    # ##     sort!(freq, :count, rev=true)
    # ## 
    # ##     codes   = String.(freq.code)
    # ##     counts  = freq.count
    # ##     labels  = ["$(codes[i]): $(counts[i])" for i in eachindex(codes)]
    # ##     colors  = Plots.palette(:hawaii, length(codes))
    # ## 
    # ##     p = StatsPlots.pie(labels, counts; color=colors, legend=:outerright,
    # ##                        title="Clients per Code", size=(900, 700), legendfontsize=10)
    # ## 
    # ##     return p
    # ## end
end

function closingprint()
    println()
    println("############################################")
    println("########                            ########")
    println("########    Esperienza terminata    ########")
    println("########                            ########")
    println("############################################")
    println()
end

end
