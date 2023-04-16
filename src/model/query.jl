#
# This file is a part of MolecularGraph.jl
# Licensed under the MIT License http://opensource.org/licenses/MIT
#

"""
    QueryAny

Query component type that generate tautology function (arg -> true/false).
"""
struct QueryAny
    value::Bool
end

Base.:(==)(q::QueryAny, r::QueryAny) = q.value == r.value
Base.hash(q::QueryAny, h::UInt) = hash(q.value, h)


"""
    QueryLiteral

General query component type (arg -> key[arg] == value).
"""
struct QueryLiteral
    operator::Symbol  # :eq, :gt?, :lt? ...
    key::Symbol
    value::Union{Symbol,Int,String,Bool,Nothing}
end
QueryLiteral(key) = QueryLiteral(:eq, key, true)
QueryLiteral(key, value) = QueryLiteral(:eq, key, value)

function Base.isless(q::QueryLiteral, r::QueryLiteral)
    q.key < r.key && return true
    q.key > r.key && return false
    q.operator < r.operator && return true
    q.operator > r.operator && return false
    return string(q.value) < string(r.value)
end
Base.:(==)(q::QueryLiteral, r::QueryLiteral
    ) = q.key == r.key && q.operator == r.operator && string(q.value) == string(r.value)
Base.hash(q::QueryLiteral, h::UInt) = hash(q.key, hash(q.operator, hash(q.value, h)))


"""
    QueryOperator

Query component type for logical operators (arg -> q1[arg] && q2[arg]).
"""
struct QueryOperator
    key::Symbol  # :and, :or, :not
    value::Vector{Union{QueryAny,QueryLiteral,QueryOperator}}
end

Base.:(==)(q::QueryOperator, r::QueryOperator) = q.key == r.key && issetequal(q.value, r.value)
Base.hash(q::QueryOperator, h::UInt) = hash(q.key, hash(Set(q.value), h))


"""
    QueryTree

Query component containar type for molecular graph properties.
"""
struct QueryTree
    tree::Union{QueryAny,QueryLiteral,QueryOperator}
end

Base.getindex(a::QueryTree, prop::Symbol) = getproperty(a, prop)


# MolGraph type aliases

const SMARTSMolGraph = MolGraph{Int,QueryTree,QueryTree}


"""
    QueryTruthTable(fml::Function, props::Vector{QueryLiteral}) -> QueryTruthTable

Truth table evaluator for query match and containment. 

This is expected to be generated by using `generate_truthtable`. Note that the properties
must be unique and sorted if QueryTruthTable constructors is manually called for testing.

- function: function that takes a vector whose size is `length(props)`
  that corresponds to each property variables and returns true or false.
- props: QueryLiteral vector.
"""
struct QueryTruthTable
    func::Function
    props::Vector{QueryLiteral}
end

# Convenient constructors just for testing
QueryTruthTable(fml::Function, props::Vector{T}
    ) where T <: Tuple = QueryTruthTable(fml, [QueryLiteral(p...) for p in props])

function QueryTruthTable(tree::Union{QueryAny,QueryLiteral,QueryOperator})
    tree isa QueryAny && return QueryTruthTable(x -> tree.value, [])
    props = sort(union(QueryLiteral[], values(querypropmap(tree))...))
    qfunc = generate_queryfunc(tree, props)
    return QueryTruthTable(qfunc, props)
end


"""
    querypropmap(tree, props) -> Dict{Symbol,Vector{QueryLiteral}}

Parse QueryLiteral tree and put QueryLiterals into bins labeled with their literal keys.
"""
function querypropmap(tree)
    if tree isa QueryAny
        return Dict{Symbol,Vector{QueryLiteral}}()
    elseif tree.key in (:and, :or)
        m = Dict{Symbol,Set{QueryLiteral}}()
        for d in tree.value
            for (k, props) in querypropmap(d)
                !haskey(m, k) && (m[k] = Set{QueryLiteral}())
                push!(m[k], props...)
            end
        end
        return Dict(k => sort(collect(d)) for (k, d) in m)
    elseif tree.key === :not
        return querypropmap(tree.value[1])
    else  # tree isa QueryLiteral
        return Dict{Symbol,Vector{QueryLiteral}}(tree.key => [tree])
    end
end


"""
    generate_queryfunc(tree, props) -> Function

Generate query truthtable function from QueryLiteral tree and the property vector.

The query truthtable function take a Vector{Bool} of length equal to `props` and
returns output in Bool.
"""
function generate_queryfunc(tree, props)
    tree isa QueryAny && return arr -> tree.value
    if tree isa QueryLiteral
        idx = findfirst(x -> x == tree, props)
        return arr -> arr[idx]
    elseif tree.key === :not
        f = generate_queryfunc(tree.value[1], props)
        return arr -> ~f(arr)
    else
        fs = [generate_queryfunc(q, props) for q in tree.value]
        cond = Dict(:and => all, :or => any)
        return arr -> cond[tree.key](f(arr) for f in fs)
    end
end


"""
    smiles_dict(tree) -> Dict{Symbol,Any}

Convert QueryLiteral to Dict{Symbol,Any} to be provided to SMILES Atom/Bond constructor.
"""
function smiles_dict(tree)
    if tree isa QueryLiteral
        return Dict{Symbol,Any}(tree.key => tree.value)
    elseif tree.key === :not  # -> :not is only for aromatic in SMILES
        d = only(smiles_dict(tree.value[1]))
        return Dict{Symbol,Any}(d.first => ~d.second)
    else  # :and
        d = Dict{Symbol,Any}()
        for q in tree.value
            merge!(d, smiles_dict(q))
        end
        return d
    end
end



"""
    specialize_nonaromatic!(q::MolGraph) -> Nothing

Convert `[#atomnumber]` queries connected to explicit single bonds to be non-aromatic
(e.g. -[#6]- -> -C-).

Should be applied before `remove_hydrogens!`.
This function is intended for generalization of PAINS query in PubChem dataset.
"""
function specialize_nonaromatic!(q::SimpleMolGraph{T,V,E}) where {T,V<:QueryTree,E<:QueryTree}
    aromsyms = Set([:B, :C, :N, :O, :P, :S, :As, :Se])
    exqs = Set(QueryOperator(:and, [
        QueryLiteral(:order, i),
        QueryOperator(:not, [QueryLiteral(:isaromatic)])
    ]) for i in 1:3)
    exbonds = Dict{Edge{T},Int}()
    for e in edges(q)
        tr = get_prop(q, e, :tree)
        tr in exqs || continue
        exbonds[e] = tr.value[1].value
    end
    for i in vertices(q)
        p = get_prop(q, i, :tree)
        p isa QueryLiteral && p.key === :symbol || continue
        # number of explicitly non-aromatic incident bonds
        cnt = sum(get(exbonds, undirectededge(q, i, nbr), 0) for nbr in neighbors(q, i); init=0)
        p.value === :C && (cnt -= 1)  # carbon allows one non-aromatic
        if p.value in aromsyms && cnt > 0
            set_prop!(q, i, QueryTree(QueryOperator(:and, [
                p, QueryOperator(:not, [QueryLiteral(:isaromatic)])
            ])))
        end
    end
end


"""
    resolve_not_hydrogen -> QueryMol

Return the molecular query with hydrogen nodes removed.

This function is intended for generalization of PAINS query in PubChem dataset.
"""
function resolve_not_hydrogen(tree)
    tree isa QueryOperator || return tree
    if tree.key === :not
        cld = tree.value[1]
        cld isa QueryLiteral && cld.key === :symbol && cld.value === :H && return QueryAny(true)
    end
    return QueryOperator(tree.key, [resolve_not_hydrogen(v) for v in tree.value])
end


"""
    remove_hydrogens!(q::MolGraph) -> Nothing

Remove hydrogens from the molecular query. 

Should be applied after `specialize_nonaromatic!`.
This function is intended for generalization of PAINS query in PubChem dataset.
"""
function remove_hydrogens!(q::SimpleMolGraph{T,V,E}) where {T,V<:QueryTree,E<:QueryTree}
    # count H nodes and mark H nodes to remove
    hnodes = T[]
    hcntarr = zeros(Int, nv(q))
    for n in vertices(q)
        t = get_prop(q, n, :tree)
        t == QueryLiteral(:symbol, :H) || continue
        hcntarr[neighbors(q, n)[1]] += 1
        push!(hnodes, n)
    end
    for n in setdiff(vertices(q), hnodes)  # heavy atom nodes
        # no longer H nodes exist, so [!#1] may be [*]
        t = resolve_not_hydrogen(get_prop(q, n, :tree))
        # consider H nodes as a :total_hydrogens query
        # C([H])([H]) -> [C;!H1;!H2]
        hs = collect(0:(hcntarr[n] - 1))
        if !isempty(hs)
            clds = [QueryOperator(:not, [QueryLiteral(:total_hydrogens, i)]) for i in hs]
            t = QueryOperator(:and, [t, clds...])
        end
        set_prop!(q, n, QueryTree(t))
    end
    return rem_vertices!(q, hnodes)
end


"""
    optimize_query(tree) -> Union{QueryAny,QueryLiteral,QueryOperator}

Return optimized query.

- absorption of QueryAny
  (ex. :and => (:any => true, A) -> A, :or => (:any => true, A) -> :any => true
- `:not` has the highest precedence in SMARTS, but only in the case like [!C],
  De Morgan's law will be applied to remove `:and` under `:not`.
  (ex. :not => (:and => (:atomsymbol => :C, :isaromatic => false)
   -> :or => (:not => (:atomsymbol => :C), isaromatic => true)
"""
function optimize_query(tree)
    tree isa QueryOperator || return tree
    # Remove `:and` under `:not`
    if tree.key === :not
        cld = tree.value[1]
        if cld.key === :and
            vals = Union{QueryAny,QueryLiteral,QueryOperator}[]
            for c in cld.value
                push!(vals, c.key === :not ? c.value[1] : QueryOperator(:not, [c]))
            end
            return QueryOperator(:or, vals)
        end
        return tree
    end
    # Absorption
    clds = Union{QueryAny,QueryLiteral,QueryOperator}[]
    for cld in tree.value
        op = optimize_query(cld)
        op isa QueryAny && tree.key === :and && (cld.value ? continue : (return op))
        op isa QueryAny && tree.key === :or && (cld.value ? (return op) : continue)
        push!(clds, op)
    end
    isempty(clds) && return QueryAny(tree.key === :and)
    length(clds) == 1 && return clds[1]
    return QueryOperator(tree.key, clds)
end
