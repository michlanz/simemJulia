module coresimulation

using ..StableRNGs
using ..ResumableFunctions
using ..CSV
using ..JSON3
using ..Distributions
using ..ConcurrentSim
using ..DataFrames
using ..StatsPlots
using ..Plots

#include("./input.jl")
#include("./structures.jl")
#include("./output.jl")
#include("./prioritystore.jl")

using ..inputdata
using ..structures
using ..postprocess
using ..showdash
using ..prioritystore

export onesimulation, last_queue_len, arrivalsProcess, clientDispatcher, storeServer

function onesimulation(num::Int64, sim::Environment, rng::StableRNG, stations::Vector{Station}, clients::Vector{Client}, dash::Dash, CAP::Int64)
    # --------------------------------------------- inizializzo le unità nel sistema
    systemunits = [0]
    # ----------------------------------- lanciare
    for (i, client) in enumerate(clients)
        @process arrivalsProcess(sim, rng, client, i * 0.0001, dash, systemunits, CAP) #hp nome: initialize process
    end
    
    for station in stations
        if station.capacity > 1
            for machine in 1:station.capacity
                @process storeServer(sim, rng, station, machine, dash, systemunits, CAP)
            end
        end
    end
    # ----------------------------------- run e output
    run(sim)
    return dash
    
end

# -------------------------------------------- definisco le funzioni
# 1. ARRIVI
@resumable function arrivalsProcess(env::Environment, rng::StableRNG, client::Client, arrival::Float64, dash::Dash, systemunits::Vector{Int64}, CAP::Int64)
    @yield timeout(env, arrival)
    @process clientDispatcher(env, rng, client, dash, systemunits, CAP)
end
# 2. DISPATCHER
@resumable function clientDispatcher(env::Environment, rng::StableRNG, client::Client, dash::Dash, systemunits::Vector{Int64}, CAP::Int64)
    while client.current_station <= length(client.route)
        station = client.route[client.current_station]
        if client.current_station == 1
            while last_queue_len(dash, station) >= CAP
                @yield take!(station.notifier)   # mi sveglio solo su vero cambio coda
            end
            systemunits[1] += 1
        logging(:systemarrival, env, dash, client, "System", systemunits[1])
    end
    if station.capacity == 1
        logging(:enterqueue, env, dash, client, station.name, systemunits[1])
        @yield lock(station.node; priority=client.priority)
        logging(:exitqueue, env, dash, client, station.name, systemunits[1])
        logging(:startprocess, env, dash, client, station.machines[1], systemunits[1])
            @yield timeout(env, rand(rng, client.processing_time[client.current_station]))
            @yield unlock(station.node)
            logging(:finishprocess, env, dash, client, station.machines[1], systemunits[1])
            client.current_station += 1
        else
            @yield prioritystore.put!(station.node, client; priority=client.priority)
            logging(:enterqueue, env, dash, client, station.name, systemunits[1])
            break #breaka perche poi sara il server a richiamarlo per rifare il dispatch. serve il while per tante risorse consecutive
            #il break esce dal while ma sta nella funzione, il return esce dalla funzione
        end 
    end
    if client.current_station > length(client.route)
        systemunits[1] -= 1
        logging(:systemexit, env, dash, client, "System", systemunits[1])
    end
end
# 3. CASO DEI SERVERSTORE
@resumable function storeServer(env::Environment, rng::StableRNG, station::Station, machineidx::Int64, dash::Dash, systemunits::Vector{Int64}, CAP::Int64)
    while true
        client = @yield prioritystore.take!(station.node)
        logging(:exitqueue, env, dash, client, station.name, systemunits[1])
        logging(:startprocess, env, dash, client, station.machines[machineidx], systemunits[1])
        @yield timeout(env, rand(rng, client.processing_time[client.current_station]))
        logging(:finishprocess, env, dash, client, station.machines[machineidx], systemunits[1])
        client.current_station += 1
        @process clientDispatcher(env, rng::StableRNG, client, dash, systemunits, CAP)
    end
end

end


#DONE
#fai un order release più sensato cappando la prima coda
#pensa a come fare unnnn warmup o simile IMHO basta il release
#metti le funzioni di supporto nelle strutture o negli input
#metti le distribuzioni samplando con RNG
#fai analisi ripetute
#guarda come fare per ciclare sulle cartelle e non sugli indici del vettore (serve?)
#sistema l'aftermath per printare asincrono