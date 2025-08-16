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
using JSON3
using Distributions
using ConcurrentSim
using DataFrames
using StatsPlots
using Plots


println("## abbiamo importato, perdoni la lentezza ##")
println()

include("./input.jl")
include("./structures.jl")
include("./output.jl")
include("./prioritystore.jl")

using .inputdata
using .structures
using .postprocess
using .showdash
using .prioritystore

export faicose

# ========== COSTRUISCI OGGETTI =====================

#TODO metti e distribuzioni 
#TODO fai un order release più sensato cappando la prima coda
#TODO pensa a come fare unnnn warmup o simile 
#TODO vedi come assegnare le priorità
#TODO fai analisi ripetute

inpath::String = "inputfile"
registry::String = "code_registry_3route_5client_norm.json"
matrix::String = "lavoration_matrix.csv"
codesnames, codesdistribution, codesroute, stationsnames, codessizevalues, codessizedistributions, codesprocessingtimes, stationscapacities = buildinput(inpath, registry, matrix)

sim = Simulation()
stations = buildstations(sim, stationsnames, stationscapacities)
codesroutestations = [[stations[findfirst(x -> x.name == s, stations)] for s in r] for r in codesroute]

PRIORITY = typemax(Int64) 
clients = generateClients(RNG, CLIENTNUM, codesnames, codesdistribution, PRIORITY, codesroutestations, codessizevalues, codessizedistributions, codesprocessingtimes)

dash = init_dash(stations)
systemunits = [0]
# ========== PROCESSI ==============================================================================================================================



#TODO passa rng? non sto samplando niente lol
# 1. ARRIVI
@resumable function arrivalsProcess(env::Environment, client::Client, arrival::Float64, dash::Dash, systemunits::Vector{Int64})
    #tipo qui metto che se ci sono meno di 10 unità in coda allora lo fai iniziare, altrimenti no
    @yield timeout(env, arrival)
    #systemunits[1] += 1
    #logging(:systemarrival, env, dash, client, "System", systemunits[1])
    @process clientDispatcher(env, client, dash, systemunits)
    #NON SO COME DIRGLI "ASPETTA FINCHè NON SUCCEDE QUALCOSA"
end

last_queue_len(dash, station) = dash.queue_len_log[findlast(x -> x.station == station.name, dash.queue_len_log)].queue_length

# 2. DISPATCHER CLIENTE
@resumable function clientDispatcher(env, client::Client, dash::Dash, systemunits::Vector{Int64}) #clientlog::ClientLog
    while client.current_station <= length(client.route)
        station = client.route[client.current_station]
        CAP = 5

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

for (i, client) in enumerate(clients)
    @process arrivalsProcess(sim, client, i * 0.0001, dash, systemunits) #hp nome: initialize process
end

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

    outpath = "output2"
    postprocessCSV(dash, outpath, clients)
    plotresults(outpath)
    closingprint()
end

end