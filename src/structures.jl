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

using ..Distributions
using ..ConcurrentSim

export Client, Machine

#client structures
mutable struct Client
    id::Int64
    code::String
    priority::Int64 #puo cambiare priorita
    route::Vector{Int64}
    processing_time::Vector{UnivariateDistribution}
end

#machine structure and definition
struct Machine
    name::String
    capacity::Int64
    node::Resource
    #service_distribution::Exponential
end

end