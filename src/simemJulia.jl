module simemJulia

println()
println("############################################")
println("########                            ########")
println("########     Buongiorno Padrona     ########")
println("########                            ########")
println("############################################")
println()

using StableRNGs
using ResumableFunctions
using CSV
#using JSON3
using Distributions
using ConcurrentSim
using DataFrames
using StatsPlots
using Plots


println("## abbiamo importato, perdoni la lentezza ##")
println()

#include("./simparameters.jl")
include("./structures.jl")
include("./output.jl")
include("./prioritystore.jl")

#import .simparameters as SP
using .structures
using .postprocess
using .showdash
using .prioritystore

export faicose

# ========== COSTRUISCI OGGETTI =====================
sim = Simulation()

stationsnames = ["station1", "station2", "station3", "station4", "station5"]
stationscapacities = [1, 2, 1, 3, 1]

stations = Vector{Station}()
buildstations(stations, sim, stationsnames, stationscapacities)

clientnum = 10
route = [stations[1], stations[3], stations[4], stations[5], stations[2]]
clients = [Client(i, clientnum+1-i, route) for i in 1:clientnum]
#ho specificato la funzione client nella struttura, l'inizializazione è implicita

dash = init_dash(stations)
systemunits = [0]
# ========== PROCESSI ==============================================================================================================================

#TODO passa la dash e le unità nel sistema?
# 1. ARRIVI
@resumable function arrivalsProcess(env::Environment, client::Client, arrival::Float64, dash::Dash, systemunits::Vector{Int64})
    @yield timeout(env, arrival)
    systemunits[1] += 1
    logging(:systemarrival, env, dash, client, "System", systemunits[1])
    #push!(monitor, Log(now(env), client.id, "Ingresso", "Sistema"))
    @process clientDispatcher(env, client, dash, systemunits)
end

#TODO passa la dash e le unità nel sistema?
# 2. DISPATCHER CLIENTE
@resumable function clientDispatcher(env, client::Client, dash::Dash, systemunits::Vector{Int64}) #clientlog::ClientLog
    while client.current_station <= length(client.route)
        station = client.route[client.current_station]
        if station.capacity == 1
            logging(:enterqueue, env, dash, client, station.name, systemunits[1])
            @yield lock(station.node; priority=client.priority)
            logging(:exitqueue, env, dash, client, station.name, systemunits[1])
            logging(:startprocess, env, dash, client, station.machines[1], systemunits[1])
            @yield timeout(env, client.processing_time[client.current_station])
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


#TODO passa la dash e le unità nel sistema?
# 3. SERVER DI STORE
@resumable function storeServer(env::Environment, stidx::Int64, machineidx::Int64, dash::Dash, systemunits::Vector{Int64})
    station = stations[stidx]
    while true
        client = @yield prioritystore.take!(station.node)
        logging(:exitqueue, env, dash, client, station.name, systemunits[1])
        logging(:startprocess, env, dash, client, station.machines[machineidx], systemunits[1])
        @yield timeout(env, client.processing_time[client.current_station])
        logging(:finishprocess, env, dash, client, station.machines[machineidx], systemunits[1])
        client.current_station += 1
        @process clientDispatcher(env, client, dash, systemunits)
    end
end

# ========== LANCIO PROCESSI =====================
#TODO passa la dash e le unità nel sistema?
for (i, client) in enumerate(clients)
    @process arrivalsProcess(sim, client, i * 0.0, dash, systemunits) #hp nome: initialize process
end

#TODO passa la dash e le unità nel sistema?
for (i, station) in enumerate(stations)
    if station.capacity > 1
        for machine in 1:station.capacity
            @process storeServer(sim, i, machine, dash, systemunits)
        end
    end
end

function faicose()
    println("##### inizio della simulazione #############")
    run(sim)
    println("##### fine della simulazione ###############")
    println()

    outpath = "output"
    postprocessCSV(dash, outpath)
    plotresults(outpath)
    closingprint()
end

end