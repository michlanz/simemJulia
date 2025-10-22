include("src/simemjulia.jl")

using .simemJulia

for i in 31:35
    println("##### inizio simulazioni cap $(i) #############")
    capqueue = i
    runmanysim(capqueue)
end

println()
println("############################################")
println("########                            ########")
println("########    Esperienza terminata    ########")
println("########                            ########")
println("############################################")
println()