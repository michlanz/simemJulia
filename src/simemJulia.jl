module simemJulia

println("Buongiorno Padrona")

using StableRNGs
using ResumableFunctions
using CSV
#using JSON3
using Distributions
using ConcurrentSim
using DataFrames
using StatsPlots
using Plots

println("Abbiamo importato, perdoni la lentezza")

#include("./simparameters.jl")
include("./structures.jl")
#include("./output.jl")
include("./prioritystore.jl")

#import .simparameters as SP
using .contextstruct
#using .outputstruct
#using .postprocess
#using .showdash
using .prioritystore
#lock(sto::PriorityStore{N, T}, item; priority=typemax(T)) where {N, T<:Number} = prioritystore.put!(sto, item; priority=priority)

export faicose



# ========== STRUTTURE =====================
## struct Station
##     name::Symbol
##     capacity::Int64
##     node::Union{Resource, PriorityStore}
##     machines::Vector{String}
## end
## 
## mutable struct Client
##     id::Int64
##     priority::Int64
##     route::Vector{Station}
##     current_station::Int64
##     systemarrival::Float64
##     systemexit::Float64
##     enterqueue::Vector{Float64}
##     exitqueue::Vector{Float64}
## end
## 
## function Client(id::Int64, priority::Int64, route::Vector{Station})::Client
##     return Client(id, priority, route, 1, NaN, NaN, [NaN for _ in route], [NaN for _ in route])
## end

struct Log
    timestamp::Float64
    id_client::Int64
    event::String
    machine::String
end

# ========== COSTRUISCI OGGETTI =====================
sim = Simulation()

monitor = Vector{Log}()

stationsnames = [:station1, :station2, :station3, :station4, :station5]
stationscapacities = [1, 2, 1, 3, 1]

stations = Vector{Station}()
buildstations(stations, sim, stationsnames, stationscapacities)

clientnum = 10
route = [stations[1], stations[2], stations[3], stations[4], stations[5]]
clients = [Client(i, clientnum+1-i, route) for i in 1:clientnum]
#ho specificato la funzione client nella struttura, l'inizializazione è implicita



# ========== PROCESSI ==============================================================================================================================

# 1. ARRIVI
@resumable function arrivalsProcess(env::Environment, client::Client, arrival::Float64)
    @yield timeout(env, arrival)
    #TODO implementa un contatore di unità nel sistema
    clientlogging(client, now(env), :systemarrival) #TODO chissa se va lol
    #client.log.systemarrival = now(env)
    push!(monitor, Log(now(env), client.id, "Ingresso", "Sistema"))
    @process clientDispatcher(env, client)
end

# 2. DISPATCHER CLIENTE
@resumable function clientDispatcher(env, client::Client) #clientlog::ClientLog
    while client.current_station <= length(client.route)
    #forse farei anche i clienti che sono già in struttura mutabile con anche le colonne tempo di arrivo, tempo di uscita, cumulata lavorazioni (e cumulata attesa per sottrazione)
        station = client.route[client.current_station]
        push!(monitor, Log(now(env), client.id, "Arriva", string(station.name)))
        clientlogging(client, now(env), :enterqueue)
        #client.log.enterqueue[client.current_station] = now(env)
        #
        if station.capacity == 1
            @yield lock(station.node; priority=client.priority)
            clientlogging(client, now(env), :exitqueue)
            #client.log.exitqueue[client.current_station] = now(env)
            push!(monitor, Log(now(env), client.id, "Inizia", station.machines[1]))
            @yield timeout(env, 1.0)
            @yield unlock(station.node)
            push!(monitor, Log(now(env), client.id, "Finisce", station.machines[1]))
            client.current_station += 1
        else
            @yield prioritystore.put!(station.node, client; priority=client.priority)
            break #breaka perche poi sara il server a richiamarlo per rifare il dispatch. serve il while per tante risorse consecutive
            #il break esce dal while ma sta nella funzione, il return esce dalla funzione
        end
    end
    if client.current_station >= length(client.route)
        #TODO implementa il contatore di unità nel sistema
        clientlogging(client, now(env), :systemexit)
        #client.log.systemexit = now(env)
        push!(monitor, Log(now(env), client.id, "Uscita", "Sistema"))
    end
end



# 3. SERVER DI STORE
@resumable function storeServer(env, stidx, machineidx)
    station = stations[stidx]
    while true
        client = @yield prioritystore.take!(station.node)
        clientlogging(client, now(env), :exitqueue)
        #client.log.exitqueue[client.current_station] = now(env)
        push!(monitor, Log(now(env), client.id, "Inizia", station.machines[machineidx]))
        @yield timeout(env, 2.0)
        push!(monitor, Log(now(env), client.id, "Finisce", station.machines[machineidx]))
        client.current_station += 1
        @process clientDispatcher(env, client)
    end
end

# ========== LANCIO PROCESSI =====================

for (i, client) in enumerate(clients)
    @process arrivalsProcess(sim, client, i * 0.25) #hp nome: initialize process
end

for (i, station) in enumerate(stations)
    if station.capacity > 1
        for machine in 1:station.capacity
            @process storeServer(sim, i, machine)
        end
    end
end

function faicose()
    println("SIAMO DENTRO WOOOO")
    run(sim, 30)

    # ========== PRINT MONITOR =====================

    println("Amo qui il monitor --------------------------------------------")
    monitor .|> println
    println()

    
    println("Amo qui i clienti --------------------------------------------")
    df_clients = DataFrame(clients)
    df_clients = select!(df_clients, Not(:route))
    df_clients .|> println
    println()

    
    println("Amo qui le macchine --------------------------------------------")
    stations .|> println



    #df = DataFrame(monitor)
    #println(eachrow(df))

    # println("solo stazione 3")
    # filter(x -> x.machine == "S3", monitor) .|> println
    # print()
    # 
    # 
    # println("solo stazione 4")
    # filter(x -> contains(x.machine, "S4M"), monitor) .|> println
    # print()


    df = DataFrame(
        timestamp = [m.timestamp for m in monitor],
        id_client = [m.id_client for m in monitor],
        machine = [m.machine for m in monitor],
        event = [m.event for m in monitor]
    )
    sort!(df, [:machine, :timestamp])

    intervals = DataFrame(machine=String[], client=Int[], priority=Int[], start=Float64[], finish=Float64[])

    for m in unique(df.machine)
        df_m = df[df.machine .== m, :]
        for i in 1:2:(nrow(df_m)-1)
            if df_m.event[i] == "Inizia" && df_m.event[i+1] == "Finisce"
                client_id = df_m.id_client[i]
                priority = clients[client_id].priority
                push!(intervals, (m, client_id, priority, df_m.timestamp[i], df_m.timestamp[i+1]))
            end
        end
    end

    machines = unique(intervals.machine)
    clients_ids = unique(intervals.client)
    id_map = Dict(id => i for (i, id) in enumerate(clients_ids))
    palette = distinguishable_colors(length(clients_ids); dropseed=true)  # niente nero

    # funzione per rettangolo
    rect(w, h, x, y) = Shape(x .+ [0, w, w, 0], y .+ [0, 0, h, h])

    # crea shapes e colori
    shapes = [
        rect(row.finish - row.start, 0.8, row.start, findfirst(==(row.machine), machines) - 0.4)
        for row in eachrow(intervals)
    ]
    colors = [palette[id_map[row.client]] for row in eachrow(intervals)]

    # plot base
    plot(shapes, c=permutedims(colors), legend=false,
         yticks=(1:length(machines), machines),
         xlabel="Time", ylabel="Machines", title="Client Processing Timeline",
         size=(1000, 300))

    # etichette centrali
    for row in eachrow(intervals)
        y = findfirst(==(row.machine), machines)
        xmid = (row.start + row.finish) / 2
        ymid = y
        text_label = "job$(row.client) p$(row.priority)"
        annotate!(xmid, ymid, text(text_label, 8, :white, :center))
    end

    display(current())
    sleep(100)

end


end