module prioritystore

#questa roba è indipendente e quindi non ha i puntini
# using ConcurrentSim
import ConcurrentSim.get_any_item as get_any_item
import ConcurrentSim.Environment as Environment
import ConcurrentSim.Store as Store
import ConcurrentSim.Put as Put
import ConcurrentSim.Get as Get
import ConcurrentSim.StorePutKey as StorePutKey
import ConcurrentSim.StoreGetKey as StoreGetKey
import ConcurrentSim.ResourceEvent as ResourceEvent
import ConcurrentSim.AbstractResource as AbstractResource
import ConcurrentSim.DataStructures as DataStructures

import ConcurrentSim.state as state
import ConcurrentSim.schedule as schedule
import ConcurrentSim.scheduled as scheduled
import ConcurrentSim.append_callback as append_callback

export PriorityStore

#N sono le cose che vanno in coda
#il container key e' definito come sottocategoria una resource key.
#la resource key è una funzione che definisce l'ordinamento degli item: secondo la priorità se c'e' o fifo di default
#T quindi indica la priorita della risorsa N, e la coppia e' in una struttura
# noi usiamo StorePutKey che è ancora un sottotipo di resourcekey ma ha ID, ITEM, PRIORITY e funziona menglio (per noi) di container key

#quando definiamo la funzione PriorityStore{N}(Env; capacity), N non è niente. "where {N}" significa "N è qualunque roba"
#prima dell'uguale c'e la "firma", dopo l'uguale il corpo (che è "che cosa fa la funzion")
# l'uguale poteva essere un "a capo e return ...", ma cosi e scritta in linea 

#il priorityStore ha intrinseco il concetto di priorita (perche lo stiamo facendo apposta ffs)
#quando lo istanzio, non mi serve dirgli quale sara il tipo della priorita, lui lo impone intero di default se non gli dico niente
#sara' poi nelle funzioni put e do_put che sara' assegnata la priorita agli item.
#se non metto niente, sara' fissata a un valore arbitratio e lo store sara' fifo.

#ora definiamo put!; do_put e do_get

const PriorityStore = Store{N, T, DataStructures.PriorityQueue{N, StorePutKey{N, T}}} where {N, T<:Number}
PriorityStore{N}(env::Environment; capacity=typemax(UInt)) where {N} = PriorityStore{N, UInt}(env; capacity)

macro callback(expr::Expr)
  expr.head !== :call && error("Expression is not a function call!")
  esc(:(append_callback($(expr.args...))))
end

function put!(sto::PriorityStore{N, T}, item::N; priority=zero(T)) where {N, T<:Number}
  put_ev = Put(sto.env)
  sto.put_queue[put_ev] = StorePutKey{N, T}(sto.seid+=one(UInt), item, T(priority))
  @callback trigger_get(put_ev, sto)
  trigger_put(put_ev, sto)
  put_ev
end

function do_put(sto::PriorityStore{N, T}, put_ev::Put, key::StorePutKey{N, T}) where {N, T<:Number}
  if sto.load < sto.capacity
    sto.load += one(UInt)
    DataStructures.enqueue!(sto.items, key.item, key)
    schedule(put_ev)
  end
  false
end

function do_get(sto::PriorityStore{N, T}, get_ev::Get, key::StoreGetKey{T}) where {N, T<:Number}
  key.filter !== get_any_item && error("Filtering not supported for `PriorityStore`. Use an unordered store instead, or submit a feature request for implementing filtering to our issue tracker.")
  isempty(sto.items) && return true
  item = DataStructures.dequeue!(sto.items)
  sto.load -= one(UInt)
  schedule(get_ev; value=item)
  true
end

take!(sto::PriorityStore{N, T}, filter::Function=get_any_item; priority=0) where {N, T<:Number} = get(sto, filter; priority)

function get(sto::PriorityStore{N, T}, filter::Function=get_any_item; priority=zero(T)) where {N, T<:Number}
  get_ev = Get(sto.env)
  sto.get_queue[get_ev] = StoreGetKey(sto.seid+=one(UInt), filter, T(priority))
  @callback trigger_put(get_ev, sto)
  trigger_get(get_ev, sto)
  get_ev
end

function trigger_put(put_ev::ResourceEvent, res::AbstractResource)
  queue = DataStructures.PriorityQueue(res.put_queue)
  while length(queue) > 0
    (put_ev, key) = DataStructures.peek(queue)
    proceed = do_put(res, put_ev, key)
    state(put_ev) === scheduled && DataStructures.dequeue!(res.put_queue, put_ev)
    proceed ? DataStructures.dequeue!(queue) : break
  end
end

function trigger_get(get_ev::ResourceEvent, res::AbstractResource)
  queue = DataStructures.PriorityQueue(res.get_queue)
  while length(queue) > 0
    (get_ev, key) = DataStructures.peek(queue)
    proceed = do_get(res, get_ev, key)
    state(get_ev) === scheduled && DataStructures.dequeue!(res.get_queue, get_ev)
    proceed ? DataStructures.dequeue!(queue) : break
  end
end

end
