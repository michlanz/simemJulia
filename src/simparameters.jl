module simparameters

using Distributions
using StableRNGs

rng = StableRNG(123)

num_clients = 30 # total number of clients generated
type_client = ["A", "B"]
production_mix = [0.3, 0.7]
dist_mix = Categorical(production_mix)
route_clients = [[3, 2, 1], [2, 3, 1]]
services::Vector{Vector{UnivariateDistribution}} = [
    [Exponential(0.5), Exponential(2.0), Exponential(0.5)],
    [Exponential(2.0), Exponential(0.5), Exponential(0.5)]
] #gia abbinato sulle macchine corrispondenti

priority = 1
interarrival_time = Exponential(0.1)


#io voglio una funzione che mi genera i lotti come da struttura definita. 

# set queue parameters
#arrival_dist = Exponential(0.5)# interarrival time distribution
#service_dist = Exponential(0.5) # service time distribution
service_route = [2, 1, 3] #metto l'ordinamento 

#machine stuff
machine_names = ["M1", "M2", "M3"] #TODO mettile in ordine alfabetico
machine_capacities = [1, 3, 1]
machine_services = [Exponential(0.5), Exponential(2), Exponential(0.5)]

end