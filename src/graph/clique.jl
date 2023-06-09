#
# This file is a part of MolecularGraph.jl
# Licensed under the MIT License http://opensource.org/licenses/MIT
#

export
    find_cliques, maximal_cliques, maximum_clique,
    find_conn_cliques, maximal_conn_cliques, maximum_conn_clique


mutable struct FindCliqueState{T,G<:SimpleGraph{T}}
    graph::G
    targetsize::Union{Int,Nothing} # if Q reached the size, finish and return cliques found so far.
    expire::Union{UInt64,Nothing} # UInt64, nanoseconds
    Q::Vector{T}
    cliques::Vector{Vector{T}}
    status::Symbol
end

function FindCliqueState(g::G; timeout=nothing, targetsize=nothing, kwargs...) where G
    expire = isnothing(timeout) ? nothing : (time_ns() + timeout * 1_000_000_000)::UInt64
    return FindCliqueState{eltype(g),G}(g, targetsize, expire, [], [], :ongoing)
end


mutable struct FindConnCliqueState{T,G<:SimpleGraph{T}}
    graph::G
    targetsize::Union{Int,Nothing} # if Q reached the size, finish and return cliques found so far.
    connected::Vector{Vector{T}}
    disconn::Vector{Vector{T}}
    expire::Union{UInt64,Nothing} # UInt64, nanoseconds
    cliques::Vector{Vector{T}}
    status::Symbol
end

function FindConnCliqueState(g::G, isconn::Dict{Edge{T},Bool};
        timeout=nothing, targetsize=nothing, kwargs...) where {T,G}
    expire = isnothing(timeout) ? nothing : (time_ns() + timeout * 1_000_000_000)::UInt64
    # connectivity adjlist
    conn = [T[] for _ in vertices(g)]
    disconn = [T[] for _ in vertices(g)]
    for i in vertices(g)
        for nbr in neighbors(g, i)
            container = isconn[u_edge(T, i, nbr)] ? conn : disconn
            push!(container[i], nbr)
        end
    end
    return FindConnCliqueState{T,G}(g, targetsize, conn, disconn, expire, [], :ongoing)
end


function expand!(state::FindCliqueState, subg, cand)
    (state.status == :timedout || state.status == :targetreached) && return
    if isempty(subg)
        # Report max clique
        push!(state.cliques, copy(state.Q))
        return
    elseif state.expire !== nothing && time_ns() > state.expire
        state.status = :timedout
        return
    elseif state.targetsize !== nothing && length(state.Q) >= state.targetsize
        state.status = :targetreached
        push!(state.cliques, copy(state.Q))
        return
    end
    candnbrcnt(n) = length(intersect(cand, neighbors(state.graph, n)))
    pivot = sortstablemax(subg, by=candnbrcnt)
    copv = setdiff(cand, neighbors(state.graph, pivot))
    for q in copv
        push!(state.Q, q)
        qnbrs = neighbors(state.graph, q)
        subgq = intersect(subg, qnbrs)
        candq = intersect(cand, qnbrs)
        expand!(state, subgq, candq)
        pop!(cand, q)
        pop!(state.Q)
    end
end

function expandconn!(state::FindConnCliqueState, R, P, Q, X, Y)
    (state.status == :timedout || state.status == :targetreached) && return
    if isempty(P) && isempty(X)
        # Report max clique
        push!(state.cliques, copy(R))
        return
    elseif state.expire !== nothing && time_ns() > state.expire
        state.status = :timedout
        return
    elseif state.targetsize !== nothing && length(R) >= state.targetsize
        state.status = :targetreached
        push!(state.cliques, copy(R))
        return
    end
    while !isempty(P)
        n = pop!(P)
        Rnew = union(R, [n])
        Qnew = intersect(Q, state.disconn[n])
        Pnew = union(
            intersect(P, neighbors(state.graph, n)),
            intersect(Q, state.connected[n]))
        Ynew = intersect(Y, state.disconn[n])
        Xnew = union(
            intersect(X, neighbors(state.graph, n)),
            intersect(Y, state.connected[n]))
        expandconn!(state, Rnew, Pnew, Qnew, Xnew, Ynew)
        push!(X, n)
    end
end


"""
    find_cliques(graph::UndirectedGraph; kwargs...) -> FindCliqueState

Calculate maximal cliques.

# Reference

1. Tomita, E., Tanaka, A., & Takahashi, H. (2006). The worst-case time
   complexity for generating all maximal cliques and computational experiments.
   Theoretical Computer Science, 363(1), 28–42.
   https://doi.org/10.1016/J.TCS.2006.06.015
1. Cazals, F., & Karande, C. (2008). A note on the problem of reporting maximal
   cliques. Theoretical Computer Science, 407(1–3), 564–568.
   https://doi.org/10.1016/j.tcs.2008.05.010
"""
function find_cliques(g::SimpleGraph; kwargs...)
    state = FindCliqueState(g; kwargs...)
    expand!(state, Set(vertices(g)), Set(vertices(g)))
    if state.status == :ongoing
        state.status = :done
    end
    return state
end

"""
    maximal_cliques(g: kwargs...) -> Vector{Vector{Int}}

Return all maximal cliques.

"""
function maximal_cliques(g; kwargs...)
    state = find_cliques(g; kwargs...)
    return state.cliques
end

"""
    maximum_clique(g; kwargs...) -> Vector{Int}

Return a maximum clique.

"""
maximum_clique(g; kwargs...
    ) = sortstablemax(maximal_cliques(g; kwargs...), by=length, init=[])



"""
    find_conn_cliques(g::SimpleGraph{T}, isconn::Dict{Edge{T},Bool};
        kwargs...) where T -> FindConnCliqueState

Calculate maximal connected cliques.

# Reference

1. Cazals, F., & Karande, C. (2005). An algorithm for reporting maximal
   c-cliques. Theoretical Computer Science, 349(3), 484–490.
   https://doi.org/10.1016/j.tcs.2005.09.038

"""
function find_conn_cliques(g::SimpleGraph{T}, isconn::Dict{Edge{T},Bool};
        kwargs...) where T
    state = FindConnCliqueState(g, isconn; kwargs...)
    nodes = Set(vertices(g))
    done = T[]
    for n in nodes
        R = T[n]
        P = intersect(setdiff(nodes, done), state.connected[n])
        Q = intersect(setdiff(nodes, done), state.disconn[n])
        X = intersect(state.connected[n], done)
        Y = intersect(state.disconn[n], done)
        expandconn!(state, R, P, Q, X, Y)
        push!(done, n)
    end
    if state.status == :ongoing
        state.status = :done
    end
    return state
end


"""
    maximal_conn_cliques(g: kwargs...) -> Vector{Vector{Int}}

Return all maximal connected cliques.

"""
function maximal_conn_cliques(g, isconn; kwargs...)
    state = find_conn_cliques(g, isconn; kwargs...)
    return state.cliques
end

"""
    maximum_conn_clique(g; kwargs...) -> Vector{Int}

Return a maximum connected clique.

"""
maximum_conn_clique(g, isconn; kwargs...
    ) = sortstablemax(maximal_conn_cliques(g, isconn; kwargs...), by=length, init=[])