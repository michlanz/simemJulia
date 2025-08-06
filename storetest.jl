include("./src/prioritystore.jl")

using ConcurrentSim
using ResumableFunctions
using DataFrames
using Plots

using .prioritystore
lock(sto::PriorityStore{N, T}, item; priority=typemax(T)) where {N, T<:Number} = prioritystore.put!(sto, item; priority=priority)
#PriorityStore è esportato, il resto no
#il Put! e il Take! devi fare prioritystore.Put! e prioritystore.Take!

struct Client
    id::Int64
    priority::Int64
    route::Vector{Symbol}
end

struct Log
    timestamp::Float64
    id_client::Int64
    event::String
    machine::String
end

struct Station
    name::Symbol
    capacity::Int64
    node::Union{Resource, PriorityStore}
    machines::Vector{String}
end

# =============================== PER PROCESS  ========================================================================= 

# CLIENTI: mettono il pezzo nello store
@resumable function clientDispatcher(env::Simulation, client::Client, arrival::Float64)
    @yield timeout(env, arrival)
    push!(monitor, Log(now(env), client.id, "Arriva", "M1M2"))
    @yield lock(store, client; priority=client.priority)
    
    if client.id == 1
        push!(monitor, Log(now(env), client.id, "Arriva", "M3"))
        @yield ConcurrentSim.lock(macchina_C)
        push!(monitor, Log(now(env), client.id, "Inizia", "M3"))
        @yield timeout(env, 2.0)
        @yield unlock(macchina_C)
        push!(monitor, Log(now(env), client.id, "Finisce", "M3"))
    end
end

# MACCHINE: prelevano dal medesimo store e lavorano
@resumable function machineProcess(env::Simulation, machine_name::String)
    while true
        client = @yield prioritystore.take!(store)
        push!(monitor, Log(now(env), client.id, "Inizia", machine_name))
        @yield timeout(env, 1.0)        # tempo di lavorazione
        push!(monitor, Log(now(env), client.id, "Finisce", machine_name))
    end
end

# =============================== PER RUN ========================================================================= 

sim = Simulation()

monitor = Vector{Log}()

clientnum = 10
route = [:stazione1, :stazione2]
clients = [Client(i, clientnum+1-i, route) for i in 1:clientnum]

stationsnames = [:station1, :station2, :station3, :station4, :station5]
stationscapacities = [1, 2, 1, 3, 1]

stations = Vector{Station}()
function buildstations(env::Environment, stationsnames::Vector{Symbol}, stationscapacities::Vector{Int64})
    for i in 1:length(stationsnames)
        if stationscapacities[i] == 1
            push!(stations, Station(stationsnames[i], stationscapacities[i], Resource(env), ["S$(i)M1"]))
        else
            vectormachines = ["S$(i)M$(j)" for j in 1:stationscapacities[i]]
            push!(stations, Station(stationsnames[i], stationscapacities[i], PriorityStore{Client}(sim), vectormachines))
        end
    end    
end

buildstations(sim, stationsnames, stationscapacities)





##########          # Avvio processi
##########          # Clienti (con arrivi ogni 0.75)
##########          for client in clients
##########              @process clientDispatcher(sim, client, client.id*0.25)
##########          end
##########          
##########          # Macchine (due processi separati)
##########          for machine in machines
##########              @process machineProcess(sim, machine)
##########          end
##########          # Run
##########          #run(sim, 30)
##########          
##########          #monitor .|> println


stations .|> println
println()

    
function faiplot()
    # ===================== GANTT ======================================================================================
#    using DataFrames, Plots

    df = DataFrame(
        timestamp = [m.timestamp for m in monitor],
        id_client = [m.id_client for m in monitor],
        machine = [m.machine for m in monitor],
        event = [m.event for m in monitor]
    )
    sort!(df, [:machine, :timestamp])

    # Costruisci intervalli (Inizia -> Finisce)
    intervals = DataFrame(machine=String[], client=Int[], start=Float64[], finish=Float64[])

    for m in ["Macchina A", "Macchina B"]
        df_m = df[df.machine .== m, :]
        for i in 1:2:(nrow(df_m)-1)
            if df_m.event[i] == "Inizia" && df_m.event[i+1] == "Finisce"
                push!(intervals, (m, df_m.id_client[i], df_m.timestamp[i], df_m.timestamp[i+1]))
            end
        end
    end

    # Disegna Gantt
    plot(size=(950, 250), legend=false, xlims=(0, maximum(intervals.finish)+0.5), ylims=(0.8, 1.7))
    y_positions = Dict("Macchina A" => 1.5, "Macchina B" => 1.0)
    palette = [
        :blue2,      # blu acceso
        :deeppink3,          # rosso-arancio
        :deepskyblue,  # verde mare
        :maroon1,            # giallo oro
        :green2,          # viola chiaro
        :plum1,     # azzurro vivo
        :yellow,           # corallo
        :violet,       # verde brillante
        :gold,         # rosa acceso
        :darkorchid2       # arancio scuro
    ]

    for row in eachrow(intervals)
        y = y_positions[row.machine]
        x_start, x_end = row.start, row.finish
        color = palette[mod1(row.client, length(palette))]

        # Barra orizzontale
        plot!([x_start, x_end], [y, y], linewidth=18, color=color)

        # Etichetta al centro
        annotate!((x_start+x_end)/2, y, text("Cliente $(row.client)", 10, :black, :center))
    end

    yticks!([1.0, 1.5], ["Macchina B", "Macchina A"])
    xlabel!("Tempo")
    ylabel!("Macchine")
    title!("Diagramma di Gantt")
    display(current())

    sleep(100)
end
