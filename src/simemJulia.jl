module simemJulia

println("Buongiorno Padrona")

using Distributions
using ConcurrentSim
using StableRNGs
using ResumableFunctions
using DataFrames
using StatsPlots
using CSV

println("Abbiamo importato, perdoni la lentezza")

include("./simparameters.jl")
include("./structures.jl")
include("./output.jl")
include("./prioritystore.jl")

import .simparameters as SP
using .contextstruct
using .outputstruct
using .postprocess
using .showdash
using .prioritystore

export runprint
#@resumable function machine_downtime!(env::Environment, machine::Machine)
#    while true
#        @yield timeout(env, 10.0)
#        @yield request(machine.node, machine.capacity)   # blocca tutti i server
#        @yield timeout(env, 1.0)
#        @yield unlock(machine.node, machine.capacity)
#    end
#end

function generateClients(rng::StableRNG, num_clients::Int64, type_client::Vector{String}, dist_mix::Categorical, priority::Int64, route_clients::Vector{Vector{Int64}}, services::Vector{Vector{UnivariateDistribution}})
    clients = Vector{Client}()
    for i in 1:num_clients
        sampled_index = rand(rng, dist_mix)
        push!(clients, Client(i, type_client[sampled_index], priority, route_clients[sampled_index], services[sampled_index]))
    end
    return clients
end

@resumable function processClient!(env::Environment, rng::StableRNG, t_a::Float64, client::Client, machines::Vector{Machine}, monitor::EventMonitor, dash::Dash, units_in_system::Vector{Int64})
    @yield timeout(env, t_a) # client arrives
    arrival_time = now(env) #la funzione sa da sola di non sovrascrivere i tempi perche ha dentro anche ID
    units_in_system[1] += 1
    push!(monitor.events, SystemLog(arrival_time, client.code, client.id, "arrival"))
    push!(dash.units_in_system_log, UnitsInSystemLog(arrival_time, units_in_system[1]))

    for (i, machine) in enumerate(machines)
        arrival_machine = now(env)
        push!(monitor.events, ProcessLog(arrival_machine, client.code, client.id, "entering queue", machine.name))
        push!(dash.queue_len_log, QueueLenLog(arrival_machine, machine.name, length(machine.node.put_queue)+1)) 
        
        @yield request(machine.node) 
        start_service_time = now(env)
        push!(monitor.events, ProcessLog(start_service_time, client.code, client.id, "starting service", machine.name))
        push!(dash.queue_time_log, QueueTimeLog(client.code, machine.name, start_service_time-arrival_machine))
        push!(dash.queue_len_log, QueueLenLog(now(env), machine.name, length(machine.node.put_queue)))

        @yield timeout(env, rand(rng, client.processing_time[i]))

        @yield unlock(machine.node) #non ho mai blocking
        push!(monitor.events, ProcessLog(now(env), client.code, client.id, "finishing service", machine.name))
        push!(dash.processing_times_log, ProcessingTimeLog(client.code, machine.name, now(env) - start_service_time))
    end
    
    units_in_system[1] -= 1
    push!(monitor.events, SystemLog(now(env), client.code, client.id, "exiting"))
    push!(dash.units_in_system_log, UnitsInSystemLog(now(env), units_in_system[1]))
    push!(dash.makespan_log, MakespanLog(client.code, now(env)-arrival_time))

end

# setup and run simulation
function setuprun()
    sim = Simulation() # initialize simulation environment e per avere la struttura di risorse mi serve l'env e quindi uffa
    arrival_time = 0.0
    units_in_system = [0] # TODO forse fa errore amo

    clients = generateClients(SP.rng, SP.num_clients, SP.type_client, SP.dist_mix, SP.priority, SP.route_clients, SP.services)
    machines = [Machine(SP.machine_names[i], SP.machine_capacities[i], Resource(sim, SP.machine_capacities[i])) for i in eachindex(SP.machine_names)]
    monitor = EventMonitor([])
    dash = Dash(
        [], #processing times
        [QueueLenLog(0.0, m.name, 0) for m in machines], #queue len
        [], #queue time
        [UnitsInSystemLog(0.0, units_in_system[1])], #units in system
        [] #makespan
    ) 
    
    for client in clients
        arrival_time += rand(SP.rng, SP.interarrival_time) #qui ci sarà da fare un po' di giochi con la generaizone e la disponibilità
        @process processClient!(sim, SP.rng, arrival_time, client, machines[client.route], monitor, dash, units_in_system) #gli ordino già le macchine
    end

    run(sim) # QUESTA E' LA COSA CHE FA SIMULARE LA SIMULAZIONE!!!!!!!! !!!!!!! !!!! SIMULAZIONE QUI

    println("Simulazione fatta amo")

    write_monitor_csv("output/monitor.csv", monitor.events)
    write_saturation_csv(monitor.events[end].timestamp, dash.processing_times_log, machines)
    write_queuelen_csv(monitor.events[end].timestamp, dash.queue_len_log, machines)
    write_queuetime_csv(dash.queue_time_log)
    write_unitsinsystem_csv(dash.units_in_system_log)
    write_makespan_csv(dash.makespan_log)

    println("Dati salvati baby")
end

function runprint()
    println("Ora iniziamo")
    setuprun()

    p5 = plot_saturation()
    p2 = plot_queuelen_time()
    p3 = plot_queuelen_box()
    p4 = plot_queuetime_box()
    p1 = plot_unitsinsystem()
    p6 = plot_makespan_box()

    savefig(Plots.plot(p1, p2, p3, p4, p5, p6; grid=(2, 3), size=(2600, 1400), left_margin=15*Plots.mm, bottom_margin=15*Plots.mm), "output/dashfig.png")
end

end