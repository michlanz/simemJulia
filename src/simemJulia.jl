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
using Statistics
using PrettyTables

println("## abbiamo importato, perdoni la lentezza ##")
println()

include("./input.jl")
include("./structures.jl")
include("./output.jl")
include("./prioritystore.jl")
include("./coresimulation.jl")

using .inputdata
using .structures
using .postprocess
using .showdash
using .prioritystore
using .coresimulation

export runmanysim, savefigs, setGate

#Abbandonato: guarda nel bootstrap/guarda come puoi fare per calibrare il campione per le ripetizioni mettendo un limite di significatività invece del numero standard (33)
#vedi se puoi unire i df senza dover passare dal salvataggio csv. vedi anche come mantenere le info
#pensavo una cosa tipo "segna per tutte le macchine solo quando sono sopra le 5 in coda, poi somma tutto e fai l'integrale" e mettilo in curva di pareto con il makespan SOLO FIFO
#TODO vedi come assegnare le priorità SBO
#TODO una violazione migliore del maledetto crowd limit, così non mi piace. peso maggiore ai momenti con molte unità in coda
#TODO sistema le tabelle e il grafico di popolazione crowd dio canissimo nè

PRIORITY = typemax(Int64) 
#capqueue::Int64 = 4
ARRIVALGATE::Bool = true
REPETITIONS::Int64 = 35


inpath::String = "inputfile"
registry::String = "code_registry_3route_5client_norm.json"
matrix::String = "lavoration_matrix.csv"
outpath = "output3"

codesnames, codesdistribution, codesroute, stationsnames, codessizevalues, codessizedistributions, codesprocessingtimes, stationscapacities = buildinput(inpath, registry, matrix)

function runmanysim(capqueue::Int64)
    dashvector::Vector{Dash} = []
    for i in 1:REPETITIONS
        sim = Simulation()
        stations = buildstations(sim, stationsnames, stationscapacities)
        codesroutestations = [[stations[findfirst(x -> x.name == s, stations)] for s in r] for r in codesroute]
        dash = init_dash(stations)
        rng = StableRNG(i*150)
        CAP::Int64 = setGate(ARRIVALGATE, capqueue)
        clients = generateClients(rng, CLIENTNUM, codesnames, codesdistribution, PRIORITY, codesroutestations, codessizevalues, codessizedistributions, codesprocessingtimes)
        push!(dashvector, onesimulation(i, sim, rng, stations, clients, dash, CAP)) #SIMULAZIONE QUI
    end
    println()
    println("##### inizio dei salvataggi ################")

    outdir = joinpath(outpath, "cap_$(capqueue)")
    mkpath(outdir)
    results = postprocessDF(dashvector, CLIENTNUM)

    for (name, df) in pairs(results)
        CSV.write(joinpath(outdir, "$(name).csv"), df isa DataFrame ? df : DataFrame(value=df))
    end

    println("##### fine dei salvataggi ##################")
end

function savefigs()
    println("##### salvo figure per tutte le simulazioni in $outpath #####")
    subfolders = sort(readdir(outpath; join=true))
    for folder in subfolders
        if isdir(folder)
            println("###### salvo figure in $(basename(folder)) #######")
            plotresults(folder)
        end
    end
    println("##### salvataggio figure completato #####")
end


# ==============================================================================
end