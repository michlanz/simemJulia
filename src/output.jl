module postprocess

using ..CSV
using ..DataFrames
using ..DataFrames: sort!
using ..structures: Dash,
                    SystemLog,
                    ProcessingTimeLog,
                    QueueLenLog,
                    QueueTimeLog,
                    UnitsInSystemLog,
                    MakespanLog,
                    Station,
                    Client
                    #AdvancementLog
#using ..outputstruct: EventLog, SystemLog, ProcessLog, Dash, ProcessingTimeLog, QueueLenLog, QueueTimeLog, UnitsInSystemLog, MakespanLog
#using ..contextstruct: Machine, Client

export writecsvMonitor,
       writecsvSaturation,
       writecsvQueuelen,
       writecsvQueuetime,
       writecsvUnitsinsystem,
       writecsvMakespan,
       postprocessCSV

function writecsvMonitor(logs::Vector{SystemLog}, outpath::String)
    df_monitor = DataFrame(logs)
    sort!(df_monitor, :timestamp)
    CSV.write(joinpath(outpath, "monitor.csv"), df_monitor)
end

function writecsvSaturation(logs::Vector{ProcessingTimeLog}, outpath::String, sim_time::Float64)
    df_saturation = combine(groupby(DataFrame(logs), :machine), :processing_time => sum => :total_processing_time)
    sort!(df_saturation, :machine)
 
    df_saturation.processing_percent = 100 .* df_saturation.total_processing_time ./ sim_time

    df_saturation.down_percent = zeros(size(df_saturation, 1))    # placeholder
    df_saturation.repair_percent = zeros(size(df_saturation, 1))  # placeholder
    df_saturation.maint_percent = zeros(size(df_saturation, 1))  # placeholder

    df_saturation.idle_percent = 100 .- df_saturation.processing_percent .- df_saturation.down_percent .- df_saturation.repair_percent .-df_saturation.maint_percent
 
    CSV.write(joinpath(outpath, "saturation.csv"), df_saturation)
end

function writecsvQueuelen(logs::Vector{QueueLenLog}, outpath::String, sim_time::Float64)
    df_queuelen = DataFrame(logs)
    sort!(df_queuelen, [:station, :timestamp])
    CSV.write(joinpath(outpath, "queuelen_time.csv"), df_queuelen)

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

    open(joinpath(outpath, "queuelen_box.csv"), "w") do file
        println(file, "station,queue_length")
        for row in eachrow(df_queuelen)
            for _ in 1:Int(round(row.percent))
                println(file, "$(row.station),$(row.queue_length)")
            end
        end
    end
end


function writecsvQueuetime(logs::Vector{QueueTimeLog}, outpath::String)
    df_queuetime = DataFrame(logs)
    sort!(df_queuetime, [:station])
    CSV.write(joinpath(outpath, "queuetime_box.csv"), df_queuetime)
end

function writecsvUnitsinsystem(logs::Vector{UnitsInSystemLog}, outpath::String)
    df_units = DataFrame(logs)
    sort!(df_units, [:timestamp])
    CSV.write(joinpath(outpath, "unitsinsystem_time.csv"), df_units)
end

function writecsvMakespan(logs::Vector{MakespanLog}, outpath::String)
    df_makespan = DataFrame(logs)
    sort!(df_makespan, [:client_code])
    CSV.write(joinpath(outpath, "makespan_box.csv"), df_makespan)
end


function postprocessCSV(dash::Dash, outpath::String)
    println("##### ci apprestiamo a salvare i dati ######")
    mkpath(outpath)
    writecsvMonitor(dash.monitor_log, outpath)
    writecsvSaturation(dash.processing_times_log, outpath, dash.monitor_log[end].timestamp)
    writecsvQueuelen(dash.queue_len_log, outpath, dash.monitor_log[end].timestamp)
    writecsvQueuetime(dash.queue_time_log, outpath)
    writecsvUnitsinsystem(dash.units_in_system_log, outpath)
    writecsvMakespan(dash.makespan_log, outpath)
    println("##### salvataggio dei dati avvenuto ########")
    println()
end

end


#######################################################################################################################
module showdash

using ..CSV
using ..DataFrames
using ..StatsPlots
using ..Plots

export plotresults,
       plot_saturation,
       plot_queuelen_time,
       plot_queuelen_box,
       plot_queuetime_box,
       plot_unitsinsystem,
       plot_makespan_box,
       closingprint

function plot_saturation(outpath::String)
    df = CSV.read(joinpath(outpath, "saturation.csv"), DataFrame)
    p = groupedbar(
        df.machine,
        [df.idle_percent df.maint_percent df.repair_percent df.down_percent df.processing_percent],
        xlabel = "Machine",
        ylabel = "Percent (%)",
        title = "Resource Usage",
        label = ["Idle" "Maintenance" "Repair" "Down" "Working"],
        bar_position = :stack,
        legend = true,
        color = [:gray90 :lightskyblue2 :lightgoldenrod1 :tomato2 :palegreen2]
    )
    hline!(p, [100], color=:black, linestyle=:dash, label="100%")
    return p
end

function plot_queuelen_time(outpath::String)
    df = CSV.read(joinpath(outpath, "queuelen_time.csv"), DataFrame)
    stations = unique(df.station)
    plt = Plots.plot(title = "Queue Length Over Time", xlabel = "Time", ylabel = "Queue Length")
    show_legend = length(stations) < 20
    for m in stations
        subdf = df[df.station .== m, :]
        Plots.plot!(plt, subdf.timestamp, subdf.queue_length, label = show_legend ? m : false, seriestype=:steppost, linewidth = 2.5)
    end
    return plt
end

function plot_queuelen_box(outpath::String)
    df = CSV.read(joinpath(outpath, "queuelen_box.csv"), DataFrame)
    p = boxplot(
        df.station,
        df.queue_length,
        xlabel = "WorkStation",
        ylabel = "Queue Length",
        title = "Queue Length Distribution per WorkStation"
    )
    return p
end

function plot_queuetime_box(outpath::String)
    df = CSV.read(joinpath(outpath, "queuetime_box.csv"), DataFrame)
    p = boxplot(
        df.station,
        df.waiting_time,
        xlabel = "Machine",
        ylabel = "Waiting Time",
        title = "Waiting Time Distribution per WorkStation"
    )
    return p
end

function plot_unitsinsystem(outpath::String)
    df = CSV.read(joinpath(outpath, "unitsinsystem_time.csv"), DataFrame)
    p = Plots.plot(
        df.timestamp,
        df.units_in_system,
        xlabel = "Time",
        ylabel = "Units in System",
        title = "Units in System Over Time",
        legend = false,
        seriestype=:steppost,
        linewidth = 2.5
    )
    return p
end

function plot_makespan_box(outpath::String)
    df = CSV.read(joinpath(outpath, "makespan_box.csv"), DataFrame)
    p = boxplot(
        df.client_code,
        df.makespan,
        xlabel = "Client Code",
        ylabel = "Makespan",
        title = "Makespan Distribution per Client"
    )
    return p
end

function plot_gantt(outpath::String)
    df = CSV.read(joinpath(outpath, "monitor.csv"), DataFrame)
    sort!(df, [:place, :timestamp])
    intervals = DataFrame(machine=String[], client=Int[], code=String[], start=Float64[], finish=Float64[])
    for m in unique(df.place)
        df_m = df[df.place .== m, :]
        i = 1
        while i <= nrow(df_m) - 1
            if df_m.event[i] == "startprocess" && df_m.event[i+1] == "finishprocess"
                push!(intervals, (m, df_m.id_client[i], df_m.code[i], df_m.timestamp[i], df_m.timestamp[i+1]))
                i += 2
            else
                i += 1
            end
        end
    end


    clients_ids = unique(intervals.client)
    base_palette = Plots.palette(:cool, clients_ids, rev = true)
    id_map = Dict(id => i for (i, id) in enumerate(clients_ids))

    rect(w,h,x,y) = Shape(x .+ [0,w,w,0], y .+ [0,0,h,h])
    machines = unique(intervals.machine)

    shapes = [rect(r.finish-r.start, 0.8, r.start, findfirst(==(r.machine), machines)-0.4) for r in eachrow(intervals)]
    colors = [base_palette[mod1(id_map[r.client], length(base_palette))] for r in eachrow(intervals)]

    p = plot(shapes, c=permutedims(colors), legend=false,
             yticks=(1:length(machines), machines),
             xlabel="Time", ylabel="Machines", title="Client Processing Timeline",
             size=(1000, 300))

    for r in eachrow(intervals)
        y = findfirst(==(r.machine), machines)
        annotate!((r.start + r.finish) / 2, y, text("$(r.code)#$(r.client)", 8, :black, :center))
    end

    savefig(p, joinpath(outpath, "ganttfig.png"))
    return p
end


function plotresults(outpath::String)#; monitor::Vector{SystemLog}; clients::Vector{Client})    
    println("##### iniziando a plottare i grafici #######")
    p5 = plot_saturation(outpath)
    p2 = plot_queuelen_time(outpath)
    p3 = plot_queuelen_box(outpath)
    p4 = plot_queuetime_box(outpath)
    p1 = plot_unitsinsystem(outpath)
    p6 = plot_makespan_box(outpath)
    plot_gantt(outpath)
    savefig(Plots.plot(p1, p2, p3, p4, p5, p6; grid=(2, 3), size=(2600, 1400), left_margin=15*Plots.mm, bottom_margin=15*Plots.mm), joinpath(outpath, "dashfig.png"))
    println("##### grafici e gantt salvati ##############")

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




##  # # =========================================
##  # 
##  # 
##  # function write_monitor_csv(path::String, events::Vector{EventLog}) #TODO 1 voce = nome file
##  #     open(path, "w") do file #TODO non so se è giusto lol non posso solo dargli il nome del file?
##  #         println(file, "logtype,timestamp,client_code,client_id,event,machine_name")
##  #         for e in events
##  #             if e isa SystemLog
##  #                 println(file, "SystemLog,$(e.timestamp),$(e.client_code),$(e.client_id),$(e.event),")
##  #             elseif e isa ProcessLog
##  #                 println(file, "ProcessLog,$(e.timestamp),$(e.client_code),$(e.client_id),$(e.event),$(e.machine_name)")
##  #             end
##  #         end
##  #     end
##  # end
##  # 
##  # #dash.processing_times_log
##  # 
##  # function write_saturation_csv(sim_time::Float64, logs::Vector{ProcessingTimeLog}, machines::Vector{Machine})
##  #     df_saturation = groupby(DataFrame(logs), :machine)
##  #     df_saturation = combine(df_saturation, :processing_time => sum => :total_processing_time)
##  #     sort!(df_saturation, :machine)
##  # 
##  #     @assert all(df_saturation.machine .== [machine.name for machine in machines]) "Le macchine non corrispondono all'ordine atteso"
##  #     df_saturation.processing_percent = 100 .* df_saturation.total_processing_time ./ [machine.capacity for machine in machines] ./ sim_time
##  # 
##  #     df_saturation.down_percent = zeros(size(df_saturation, 1))    # placeholder
##  #     df_saturation.repair_percent = zeros(size(df_saturation, 1))  # placeholder
##  #     df_saturation.maint_percent = zeros(size(df_saturation, 1))  # placeholder
##  # 
##  #     df_saturation.idle_percent = 100 .- df_saturation.processing_percent .- df_saturation.down_percent .- df_saturation.repair_percent .-df_saturation.maint_percent
##  # 
##  #     CSV.write(joinpath("output", "saturation.csv"), df_saturation)
##  # end
##  # 
##  # 
##  # function write_queuelen_csv(sim_time::Float64, logs::Vector{QueueLenLog}, machines::Vector{Machine})
##  #     df_queuelen = DataFrame(logs)
##  #     sort!(df_queuelen, [:machine, :timestamp])
##  #     CSV.write(joinpath("output", "queuelen_timestamp.csv"), df_queuelen)
##  # 
##  #     df_queuelen.duration = zeros(nrow(df_queuelen))
##  # 
##  #     for machine in machines
##  #         filtering = df_queuelen.machine .== machine.name
##  #         rows = findall(filtering)
##  #         for i in 1:length(rows)-1
##  #             df_queuelen.duration[rows[i]] = df_queuelen.timestamp[rows[i+1]] - df_queuelen.timestamp[rows[i]]
##  #         end
##  #         df_queuelen.duration[rows[end]] = sim_time - df_queuelen.timestamp[rows[end]]
##  #     end
##  # 
##  #     df_queuelen = combine(groupby(df_queuelen, [:machine, :queue_length]), :duration => sum => :total_duration)
##  #     df_queuelen.percent = 100 .* df_queuelen.total_duration ./ sim_time
##  #     sort!(df_queuelen, [:machine, :queue_length])
##  # 
##  #     open(joinpath("output", "queuelen_box.csv"), "w") do file
##  #         println(file, "machine,queue_length")
##  #         for row in eachrow(df_queuelen)
##  #             for _ in 1:Int(round(row.percent))
##  #                 println(file, "$(row.machine),$(row.queue_length)")
##  #             end
##  #         end
##  #     end
##  # 
##  # end
##  # 
##  # function write_queuetime_csv(logs::Vector{QueueTimeLog})
##  #     df_queuetime = DataFrame(logs)
##  #     sort!(df_queuetime, [:machine])
##  #     CSV.write(joinpath("output", "queuetime.csv"), df_queuetime)
##  # end
##  # 
##  # function write_unitsinsystem_csv(logs::Vector{UnitsInSystemLog})
##  #     df_units = DataFrame(logs)
##  #     sort!(df_units, [:timestamp])
##  #     CSV.write(joinpath("output", "unitsinsystem.csv"), df_units)
##  # end
##  # 
##  # function write_makespan_csv(logs::Vector{MakespanLog})
##  #     df_makespan = DataFrame(logs)
##  #     sort!(df_makespan, [:client_code])
##  #     CSV.write(joinpath("output", "makespan.csv"), df_makespan)
##  # end

