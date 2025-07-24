module postprocess

using ..CSV
using ..DataFrames
using ..DataFrames: sort!
using ..outputstruct: EventLog, SystemLog, ProcessLog, Dash, ProcessingTimeLog, QueueLenLog, QueueTimeLog, UnitsInSystemLog, MakespanLog
using ..contextstruct: Machine, Client

export write_monitor_csv, write_saturation_csv, write_queuelen_csv, write_queuetime_csv, write_unitsinsystem_csv, write_makespan_csv

function write_monitor_csv(path::String, events::Vector{EventLog}) #TODO 1 voce = nome file
    open(path, "w") do file #TODO non so se è giusto lol non posso solo dargli il nome del file?
        println(file, "logtype,timestamp,client_code,client_id,event,machine_name")
        for e in events
            if e isa SystemLog
                println(file, "SystemLog,$(e.timestamp),$(e.client_code),$(e.client_id),$(e.event),")
            elseif e isa ProcessLog
                println(file, "ProcessLog,$(e.timestamp),$(e.client_code),$(e.client_id),$(e.event),$(e.machine_name)")
            end
        end
    end
end

#dash.processing_times_log

function write_saturation_csv(sim_time::Float64, logs::Vector{ProcessingTimeLog}, machines::Vector{Machine})
    df_saturation = groupby(DataFrame(logs), :machine)
    df_saturation = combine(df_saturation, :processing_time => sum => :total_processing_time)
    sort!(df_saturation, :machine)

    @assert all(df_saturation.machine .== [machine.name for machine in machines]) "Le macchine non corrispondono all'ordine atteso"
    df_saturation.processing_percent = 100 .* df_saturation.total_processing_time ./ [machine.capacity for machine in machines] ./ sim_time

    df_saturation.down_percent = zeros(size(df_saturation, 1))    # placeholder
    df_saturation.repair_percent = zeros(size(df_saturation, 1))  # placeholder
    df_saturation.maint_percent = zeros(size(df_saturation, 1))  # placeholder

    df_saturation.idle_percent = 100 .- df_saturation.processing_percent .- df_saturation.down_percent .- df_saturation.repair_percent .-df_saturation.maint_percent

    CSV.write(joinpath("output", "saturation.csv"), df_saturation)
end


function write_queuelen_csv(sim_time::Float64, logs::Vector{QueueLenLog}, machines::Vector{Machine})
    df_queuelen = DataFrame(logs)
    sort!(df_queuelen, [:machine, :timestamp])
    CSV.write(joinpath("output", "queuelen_timestamp.csv"), df_queuelen)

    df_queuelen.duration = zeros(nrow(df_queuelen))

    for machine in machines
        filtering = df_queuelen.machine .== machine.name
        rows = findall(filtering)
        for i in 1:length(rows)-1
            df_queuelen.duration[rows[i]] = df_queuelen.timestamp[rows[i+1]] - df_queuelen.timestamp[rows[i]]
        end
        df_queuelen.duration[rows[end]] = sim_time - df_queuelen.timestamp[rows[end]]
    end

    df_queuelen = combine(groupby(df_queuelen, [:machine, :queue_length]), :duration => sum => :total_duration)
    df_queuelen.percent = 100 .* df_queuelen.total_duration ./ sim_time
    sort!(df_queuelen, [:machine, :queue_length])

    open(joinpath("output", "queuelen_box.csv"), "w") do file
        println(file, "machine,queue_length")
        for row in eachrow(df_queuelen)
            for _ in 1:Int(round(row.percent))
                println(file, "$(row.machine),$(row.queue_length)")
            end
        end
    end

end

function write_queuetime_csv(logs::Vector{QueueTimeLog})
    df_queuetime = DataFrame(logs)
    sort!(df_queuetime, [:machine])
    CSV.write(joinpath("output", "queuetime.csv"), df_queuetime)
end

function write_unitsinsystem_csv(logs::Vector{UnitsInSystemLog})
    df_units = DataFrame(logs)
    sort!(df_units, [:timestamp])
    CSV.write(joinpath("output", "unitsinsystem.csv"), df_units)
end

function write_makespan_csv(logs::Vector{MakespanLog})
    df_makespan = DataFrame(logs)
    sort!(df_makespan, [:client_code])
    CSV.write(joinpath("output", "makespan.csv"), df_makespan)
end

end

#######################################################################################################################
module showdash

using ..CSV
using ..DataFrames
using ..StatsPlots

export plot_saturation, plot_queuelen_time, plot_queuelen_box, plot_queuetime_box, plot_unitsinsystem, plot_makespan_box

function plot_saturation()
    df = CSV.read(joinpath("output", "saturation.csv"), DataFrame)
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

function plot_queuelen_time()
    df = CSV.read(joinpath("output", "queuelen_timestamp.csv"), DataFrame)
    machines = unique(df.machine)
    plt = Plots.plot(title = "Queue Length Over Time", xlabel = "Time", ylabel = "Queue Length")
    show_legend = length(machines) < 20
    for m in machines
        subdf = df[df.machine .== m, :]
        Plots.plot!(plt, subdf.timestamp, subdf.queue_length, label = show_legend ? m : false, seriestype=:steppost, linewidth = 2.5)
    end
    return plt
end

function plot_queuelen_box()
    df = CSV.read(joinpath("output", "queuelen_box.csv"), DataFrame)
    p = boxplot(
        df.machine,
        df.queue_length,
        xlabel = "Machine",
        ylabel = "Queue Length",
        title = "Queue Length Distribution per Machine"
    )
    return p
end

function plot_queuetime_box()
    df = CSV.read(joinpath("output", "queuetime.csv"), DataFrame)
    p = boxplot(
        df.machine,
        df.waiting_time,
        xlabel = "Machine",
        ylabel = "Waiting Time",
        title = "Waiting Time Distribution per Machine"
    )
    return p
end

function plot_unitsinsystem()
    df = CSV.read(joinpath("output", "unitsinsystem.csv"), DataFrame)
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

function plot_makespan_box()
    df = CSV.read(joinpath("output", "makespan.csv"), DataFrame)
    p = boxplot(
        df.client_code,
        df.makespan,
        xlabel = "Client Code",
        ylabel = "Makespan",
        title = "Makespan Distribution per Client"
    )
    return p
end

end