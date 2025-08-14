module structures

include("./prioritystore.jl")

using ..Distributions
using ..ConcurrentSim

using .prioritystore

export Dash,
       SystemLog,
       ProcessingTimeLog,
       QueueLenLog,
       QueueTimeLog,
       UnitsInSystemLog,
       MakespanLog,
       Station,
       Client,
       AdvancementLog,
       buildstations,
       logging,
       init_dash

struct SystemLog
    timestamp::Float64
    id_client::Int64
    code::String
    event::Symbol
    place::String
end

struct ProcessingTimeLog
    client_code::String
    machine::String
    processing_time::Float64
end

struct QueueLenLog
    timestamp::Float64
    station::String
    queue_length::Int64
end

struct QueueTimeLog
    client_code::String
    station::String
    waiting_time::Float64
end

struct UnitsInSystemLog
    timestamp::Float64
    units_in_system::Int64
end

struct MakespanLog
    client_code::String
    makespan::Float64
end

struct Dash
    monitor_log::Vector{SystemLog}
    processing_times_log::Vector{ProcessingTimeLog}
    queue_len_log::Vector{QueueLenLog}
    queue_time_log::Vector{QueueTimeLog}
    units_in_system_log::Vector{UnitsInSystemLog}
    makespan_log::Vector{MakespanLog}
end

# =======================================================================tutto il resto

struct Station
    name::String
    capacity::Int64
    node::Union{Resource, PriorityStore}
    machines::Vector{String}
end

#FIXME potrei rimuovere systemexit, exitqueue e finishprocess
mutable struct AdvancementLog
    code::String
    systemarrival::Float64
    systemexit::Float64
    enterqueue::Vector{Float64}
    exitqueue::Vector{Float64}
    startprocess::Vector{Float64}
    finishprocess::Vector{Float64}
end

mutable struct Client
    id::Int64
    code::String
    lotsize::Int64
    priority::Int64 #anche vettore lungo come le macchine, vedi tu
    route::Vector{Station}
    processing_time::Vector{Float64}
    current_station::Int64
    log::AdvancementLog
end

# =================================================================== functions =======


function buildstations(stat::Vector{Station}, env::Environment, stationsnames::Vector{String}, stationscapacities::Vector{Int64})
    for i in 1:length(stationsnames)
        if stationscapacities[i] == 1
            push!(stat, Station(stationsnames[i], stationscapacities[i], Resource(env), ["S$(i)"]))
        else
            vectormachines = ["S$(i)M$(j)" for j in 1:stationscapacities[i]]
            push!(stat, Station(stationsnames[i], stationscapacities[i], PriorityStore{Client}(env), vectormachines))
        end
    end    
end


function AdvancementLog(code::String, n::Int64)::AdvancementLog
    return AdvancementLog(code, NaN, NaN, fill(NaN, n), fill(NaN, n), fill(NaN, n), fill(NaN, n))
end

#TODO fixa il code
function Client(id::Int64, priority::Int64, route::Vector{Station})::Client
    code = "TEMP"
    return Client(id, code, 200, priority, route, [1.0, 4.0, 8.0, 6.0, 7.0], 1, AdvancementLog(code, length(route)))
end

function logging(event::Symbol, env::Environment, dash::Dash, client::Client, place::String, units::Int64)
    if event == :systemarrival
        client.log.systemarrival = now(env)
        push!(dash.monitor_log, SystemLog(now(env), client.id, client.code, event, place))
        push!(dash.units_in_system_log, UnitsInSystemLog(now(env), units))
    elseif event == :enterqueue
        client.log.enterqueue[client.current_station] = now(env)
        push!(dash.monitor_log, SystemLog(now(env), client.id, client.code, event, place))
        push!(dash.queue_len_log, QueueLenLog(now(env), place, dash.queue_len_log[findlast(x -> x.station == place, dash.queue_len_log)].queue_length + 1))   
    elseif event == :exitqueue
        client.log.exitqueue[client.current_station] = now(env)
        push!(dash.queue_time_log, QueueTimeLog(client.code, place, client.log.exitqueue[client.current_station]-client.log.enterqueue[client.current_station]))
        push!(dash.queue_len_log, QueueLenLog(now(env), place, dash.queue_len_log[findlast(x -> x.station == place, dash.queue_len_log)].queue_length - 1))
    elseif event == :startprocess
        client.log.startprocess[client.current_station] = now(env)
        push!(dash.monitor_log, SystemLog(now(env), client.id, client.code, event, place))
    elseif event == :finishprocess
        client.log.finishprocess[client.current_station] = now(env)
        push!(dash.monitor_log, SystemLog(now(env), client.id, client.code, event, place))
        push!(dash.processing_times_log, ProcessingTimeLog(client.code, place, client.log.finishprocess[client.current_station]-client.log.startprocess[client.current_station]))
    elseif event == :systemexit
        client.log.systemexit = now(env)
        push!(dash.monitor_log, SystemLog(now(env), client.id, client.code, event, place))
        push!(dash.units_in_system_log, UnitsInSystemLog(now(env), units))
        push!(dash.makespan_log, MakespanLog(client.code, client.log.systemexit-client.log.systemarrival))
    end
end

function init_dash(stations::Vector{Station})
    return Dash(
        SystemLog[],
        ProcessingTimeLog[], # processing_times_log
        [QueueLenLog(0.0, s.name, 0) for s in stations], # queue_len_log (una entry per stazione a t=0)
        QueueTimeLog[], # queue_time_log
        [UnitsInSystemLog(0.0, 0)], # units_in_system_log (stato iniziale)
        MakespanLog[] #makespan_log
    )
end

end



#FIXME il contatore delle cose in modo organico che non rilogga sui valori di prima

    ###############################################################
    #   if client.route[client.current_station].node isa Resource
    #       push!(dash.queue_len_log, QueueLenLog(now, place, length(client.route[client.current_station].node.put_queue)))
    #   elseif client.route[client.current_station].node isa PriorityStore
    #       push!(dash.queue_len_log, QueueLenLog(now, place, dash.queue_len_log[findlast(x -> x.station == place, dash.queue_len_log)].queue_length - 1))
    #   end
    ###############################################################

##################################################################################################################