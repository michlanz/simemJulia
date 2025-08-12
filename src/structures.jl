# export outputstruct, contextstruct

##################################################################################################################

module outputstruct

export EventMonitor, SystemLog, ProcessLog, Dash, ProcessingTimeLog, QueueLenLog, QueueTimeLog, UnitsInSystemLog, MakespanLog

abstract type EventLog end

struct EventMonitor
    events::Vector{EventLog}
end

struct SystemLog <: EventLog
    timestamp::Float64
    client_code::String
    client_id::Int64
    event::String
end

struct ProcessLog <: EventLog
    timestamp::Float64
    client_code::String
    client_id::Int64
    event::String
    machine_name::String
end

######################################################

struct ProcessingTimeLog
    client_code::String
    machine::String
    processing_time::Float64
end

struct QueueLenLog
    timestamp::Float64
    machine::String
    queue_length::Int64
end

struct QueueTimeLog
    client_code::String
    machine::String
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
    processing_times_log::Vector{ProcessingTimeLog}
    queue_len_log::Vector{QueueLenLog}
    queue_time_log::Vector{QueueTimeLog}
    units_in_system_log::Vector{UnitsInSystemLog}
    makespan_log::Vector{MakespanLog}
end

end

##################################################################################################################

module contextstruct

include("./prioritystore.jl")

using ..Distributions
using ..ConcurrentSim

using .prioritystore

export Station, buildstations, Client, AdvancementLog, clientlogging

#struct Machine
#    name::String
#    capacity::Int64
#    node::Resource
#    #service_distribution::Exponential
#end


struct Station
    name::Symbol #TODO sostituisci in string
    capacity::Int64
    node::Union{Resource, PriorityStore}
    machines::Vector{String}
end

function buildstations(stat::Vector{Station}, env::Environment, stationsnames::Vector{Symbol}, stationscapacities::Vector{Int64})
    for i in 1:length(stationsnames)
        if stationscapacities[i] == 1
            push!(stat, Station(stationsnames[i], stationscapacities[i], Resource(env), ["S$(i)"]))
        else
            vectormachines = ["S$(i)M$(j)" for j in 1:stationscapacities[i]]
            push!(stat, Station(stationsnames[i], stationscapacities[i], PriorityStore{Client}(env), vectormachines))
        end
    end    
end

#mutable struct Client
#    id::Int64
#    code::String
#    priority::Int64 #puo cambiare priorita
#    route::Vector{Int64}
#    processing_time::Vector{UnivariateDistribution}
#end

#sistema tutti i push e le sovrascritte
mutable struct AdvancementLog
    systemarrival::Float64
    systemexit::Float64
    enterqueue::Vector{Float64}
    exitqueue::Vector{Float64}
end

mutable struct Client
    id::Int64
    code::String
    lotsize::Int64
    priority::Int64 #anche vettore lungo come le macchine, vedi tu
    route::Vector{Station}
    current_station::Int64
    #
    log::AdvancementLog
    #systemarrival::Float64
    #systemexit::Float64
    #enterqueue::Vector{Float64}
    #exitqueue::Vector{Float64}
end

function AdvancementLog(n::Int64)::AdvancementLog
    return AdvancementLog(NaN, NaN, fill(NaN, n), fill(NaN, n))
end


#TODO fixa il code
function Client(id::Int64, priority::Int64, route::Vector{Station})::Client
    return Client(id, "00", 200, priority, route, 1, AdvancementLog(length(route)))
end


function clientlogging(client::Client, now::Float64, event::Symbol)
    if event == :systemarrival
        client.log.systemarrival = now
    elseif event == :enterqueue
        client.log.enterqueue[client.current_station] = now
    elseif event == :exitqueue
        client.log.exitqueue[client.current_station] = now
    elseif event == :systemexit
        client.log.systemexit = now
    end
end


end