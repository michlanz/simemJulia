include("src/simemJulia.jl")

using .simemJulia

for i in 2:10
    println("##### inizio simulazioni cap $(i) #############")
    capqueue = i
    runmanysim(capqueue)
end

for i in 1:10:351
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