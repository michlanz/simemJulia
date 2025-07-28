include("./src/prioritystore.jl")

using ConcurrentSim
using ResumableFunctions
using DataFrames
using Plots

using .prioritystore
#PriorityStore è esportato, il resto no
#il Put! e il Take! devi fare prioritystore.Put! e prioritystore.Take!

struct Client
    id::Int64
    priority::Int64
end


struct Log
    timestamp::Float64
    id_client::Int64
    event::String
    machine::String
end

monitor = Vector{Log}()

sim = Simulation()
store = PriorityStore{Client}(sim)

machineA = Resource(sim, 1)
machineB = Resource(sim, 1)

clients =[
    Client(1, 6), Client(2, 1),
    Client(3, 7), Client(4, 2),
    Client(5, 8), Client(6, 3),
    Client(7, 9), Client(8, 4),
    Client(9, 10), Client(10, 5)
]

# CLIENTI: mettono il pezzo nello store
@resumable function processClient(env::Simulation, client::Client, arrival::Float64)
    @yield timeout(env, arrival)
    push!(monitor, Log(now(env), client.id, "Arriva", "M1M2"))
    @yield prioritystore.put!(store, client; priority=client.priority)
end

# MACCHINE: prelevano dal medesimo store e lavorano
@resumable function machineProcess(env::Simulation, machine_name::String)
    while true
        #println(machine_name, " nonum. Put: ", store.put_queue)
        #println(machine_name, " nonum. Get: ", store.get_queue)
        #println(machine_name, " nonum. Items: ", store.items)
        client = @yield prioritystore.take!(store)
        push!(monitor, Log(now(env), client.id, "Inizia", machine_name))
        #println(machine_name, client.id, ". Put: ", store.put_queue)
        #println(machine_name, client.id, ". Get: ", store.get_queue)
        #println(machine_name, client.id, ". Items: ", store.items)
        @yield timeout(env, 1.0)        # tempo di lavorazione
        push!(monitor, Log(now(env), client.id, "Finisce", machine_name))
        #il principio è che la putqueue serve per mettere gli elementi in coda e la getqueue è per fare il dispatching verso le macchine
        #forse è il porcess che processa a cazzo, dovremmo guardare quando le priorità vengono sminchiate
        # è l'hashing del dizionario che sminchietta
        # vedere come queue e stack fanno per i workaround 
        #ridefiniremo doget e doput come modificati per i queuestore e gli stackstore
        #voglio che se non gli do la priorità lui fa fifo
    end
end

# Avvio processi
# Clienti (con arrivi ogni 0.75)
for client in clients
    @process processClient(sim, client, client.id*0.0)
end

# Macchine (due processi separati)
@process machineProcess(sim, "Macchina A")
@process machineProcess(sim, "Macchina B")

# Run
run(sim, 30)

monitor .|> println
println()


# ===================== GANTT =====================
using DataFrames, Plots

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










## @resumable function processClient(env::Simulation, client_id::Int64, arrival::Float64)
##     @yield timeout(env, arrival)
##     if client_id == 1
##         @yield request(machineA)
##         push!(monitor, Log(now(env), 1, "Inizia", "A"))
##         #println("Cliente 1 inizia su A a tempo $(now(sim))")
##         @yield timeout(env, 1.0)
##         @yield release(machineA)
##         push!(monitor, Log(now(env), 1, "Finisce", "A"))
##         #println("Cliente 1 finisce su A a tempo $(now(sim))")
##     end 
##     if client_id == 2
##         @yield request(machineB)
##         push!(monitor, Log(now(env), 2, "Inizia", "B"))
##         #println("Cliente 2 inizia su B a tempo $(now(sim))")
##         @yield timeout(env, 1.0)
##         @yield release(machineB)
##         push!(monitor, Log(now(env), 2, "Finisce", "B"))
##         #println("Cliente 2 finisce su B a tempo $(now(sim))")
##     end
## end
## 
## function funzionediocane()
##     arrival::Float64 = 0.0
##     for id in clients
##         arrival += 0.75
##         @process processClient(sim, id, arrival)
##     end
## end



### 
### 
### # ===================== GANTT =====================
### df = DataFrame(
###     timestamp = [m.timestamp for m in monitor],
###     id_client = [m.id_client for m in monitor],
###     machine = [m.machine for m in monitor],
###     event = [m.event for m in monitor]
### )
### sort!(df, [:machine, :timestamp])
### 
### intervals = DataFrame(machine=String[], client=Int[], start=Float64[], finish=Float64[])
### 
### for m in ["A", "B"]
###     df_m = df[df.machine .== m, :]
###     for i in 1:2:(nrow(df_m)-1)
###         if df_m.event[i] == "Inizia" && df_m.event[i+1] == "Finisce"
###             push!(intervals, (m, df_m.id_client[i], df_m.timestamp[i], df_m.timestamp[i+1]))
###         end
###     end
### end
### 
### plot(size=(950, 250), legend=false, xlims=(0, maximum(intervals.finish)+0.5), ylims=(0.8, 1.7))
### y_positions = Dict("A" => 1.5, "B" => 1.0)
### palette = [:orange, :lightblue, :green, :yellow, :purple]
### 
### for row in eachrow(intervals)
###     y = y_positions[row.machine]
###     x_start, x_end = row.start, row.finish
###     color = palette[mod1(row.client, length(palette))]
### 
###     # Barra orizzontale
###     plot!([x_start, x_end], [y, y], linewidth=18, color=color)
### 
###     # Etichetta al centro (Cliente X)
###     annotate!((x_start+x_end)/2, y, text("Cliente $(row.client)", 10, :black, :center))
### end
### 
### yticks!([1.0, 1.5], ["Macchina B", "Macchina A"])
### xlabel!("Tempo")
### ylabel!("Macchine")
### title!("Diagramma di Gantt")
### display(current())
### 

