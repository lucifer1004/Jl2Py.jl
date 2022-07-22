module Jl2Py

export jl2py

using PythonCall

const AST = PythonCall.pynew()
const OP_DICT = Dict{Symbol,Py}()
const OP_UDICT = Dict{Symbol,Py}()
const TYPE_DICT = Dict{Symbol,String}()
const BUILTIN_DICT = Dict{Symbol,String}()

function __unaryop(jl_expr, op)
    operand = __jl2py(jl_expr.args[2])
    unaryop = AST.UnaryOp(op(), operand)
    return unaryop
end

function __binop(jl_expr, op)
    left = __jl2py(jl_expr.args[2])
    right = __jl2py(jl_expr.args[3])
    binop = AST.BinOp(left, op(), right)
    return binop
end

function __boolop(jl_expr, op)
    left = __jl2py(jl_expr.args[1])
    right = __jl2py(jl_expr.args[2])
    boolop = AST.BoolOp(op(), [left, right])
    return boolop
end

function __compareop_from_comparison(jl_expr)
    elts = __jl2py(jl_expr.args[1:2:end])
    ops = map(x -> OP_DICT[x](), jl_expr.args[2:2:end])
    compareop = AST.Compare(elts[1], ops, elts[2:end])
    return compareop
end

function __compareop_from_call(jl_expr, op)
    elts = __jl2py(jl_expr.args[2:end])
    compareop = AST.Compare(elts[1], [op()], elts[2:end])
    return compareop
end

function __multiop(jl_expr, op)
    left = __jl2py(jl_expr.args[2])
    right = __jl2py(jl_expr.args[3])
    binop = AST.BinOp(left, op(), right)
    argcnt = length(jl_expr.args)
    for i in 4:argcnt
        right = __jl2py(jl_expr.args[i])
        binop = AST.BinOp(binop, op(), right)
    end
    return binop
end

function __parse_arg(arg::Union{Symbol,Expr})
    if isa(arg, Symbol)
        return AST.arg(pystr(arg))
    elseif arg.head == :(::)
        return AST.arg(pystr(arg.args[1]), __parse_type(arg.args[2]))
    end
end

function __parse_args(params)
    posonlyargs = []
    defaults = []
    kwonlyargs = []
    kw_defaults = []
    kwarg = nothing
    vararg = nothing

    for arg in params
        if isa(arg, Symbol) || arg.head == :(::)
            push!(posonlyargs, __parse_arg(arg))
        elseif arg.head == :kw
            push!(posonlyargs, __parse_arg(arg.args[1]))
            push!(defaults, __jl2py(arg.args[2]))
        elseif arg.head == :...
            vararg = __parse_arg(arg.args[1])
        elseif arg.head == :parameters
            for param in arg.args
                if isa(param, Symbol)
                    push!(kwonlyargs, __parse_arg(param))
                    push!(kw_defaults, nothing)
                elseif param.head == :kw
                    push!(kwonlyargs, __parse_arg(param.args[1]))
                    push!(kw_defaults, __jl2py(param.args[2]))
                elseif param.head == :...
                    kwarg = __parse_arg(param.args[1])
                end
            end
        end
    end

    return AST.arguments(; args=PyList(),
                         posonlyargs=PyList(posonlyargs),
                         kwonlyargs=PyList(kwonlyargs),
                         defaults=PyList(defaults),
                         kw_defaults=PyList(kw_defaults),
                         kwarg=kwarg, vararg=vararg)
end

function __parse_pair(expr::Expr)
    (expr.head == :call && expr.args[1] == :(=>)) || error("Invalid pair expr")
    return __jl2py(expr.args[2]), __jl2py(expr.args[3])
end

"""
Parse a Julia range (leading by :(:)).

We modify the end when all args are `Integer`s. For example: 

- `1:3` becomes `range(1, 4)`
- `1:5:11` becomes `range(1, 12, 5)`
- `1:-5:-9` becomes `range(1, -10, -5)`

We also modify the end when the step is implicit (=1). For example:

- `a:b` becomes `range(a, b + 1)`

This might cause problems in such cases as `1.5:1.8`, but since Python only supports integer-indexed implicit ranges, 
we do not consider such edge cases here.
"""
function __parse_range(args::AbstractVector)
    if length(args) == 2
        if isa(args[1], Integer) && isa(args[2], Integer)
            return [AST.Constant(args[1]), AST.Constant(args[2] + 1)]
        end

        return [__jl2py(args[1]), AST.BinOp(__jl2py(args[2]), AST.Add(), AST.Constant(1))]
    else
        if isa(args[1], Integer) && isa(args[2], Integer) && isa(args[3], Integer)
            return [AST.Constant(args[1]), AST.Constant(args[3] + sign(args[2])), __jl2py(args[2])]
        end
        return [__jl2py(args[1]), __jl2py(args[3]), __jl2py(args[2])]
    end
end

function __parse_type(typ::Union{Symbol,Expr})
    if isa(typ, Symbol)
        return AST.Name(get(TYPE_DICT, typ, pystr(typ)))
    else
        typ.head == :curly || error("Invalid type expr")
        if length(typ.args) == 2
            slice = __parse_type(typ.args[2])
        else
            slice = AST.Tuple(map(__parse_type, typ.args[2:end]))
        end
        return AST.Subscript(__parse_type(typ.args[1]), slice)
    end
end

function __parse_generator(args::AbstractVector)
    return PyList(vcat(map(args) do arg
                           if arg.head == :(=)
                               target = __jl2py(arg.args[1])
                               iter = __jl2py(arg.args[2])
                               [AST.comprehension(target, iter, PyList(); is_async=false)]
                           else
                               __jl2py(arg)
                           end
                       end...))
end

__jl2py(args::AbstractVector) = map(__jl2py, args)

function __jl2py(jl_constant::Union{Number,String}; topofblock::Bool=false)
    return topofblock ? AST.Expr(AST.Constant(jl_constant)) : AST.Constant(jl_constant)
end

function __jl2py(jl_symbol::Symbol; topofblock::Bool=false)
    name = jl_symbol == :nothing ? AST.Constant(nothing) : AST.Name(pystr(jl_symbol))
    return topofblock ? AST.Expr(name) : name
end

function __jl2py(jl_qnode::QuoteNode; topofblock::Bool=false)
    return string(jl_qnode.value)
end

function __jl2py(jl_expr::Expr; topofblock::Bool=false, isflatten::Bool=false, iscomprehension::Bool=false)
    if jl_expr.head ∈ [:block, :toplevel]
        py_exprs = [__jl2py(expr; topofblock=true) for expr in jl_expr.args if !isa(expr, LineNumberNode)]
        return PyList(py_exprs)
    elseif jl_expr.head == :function
        returns = nothing
        if jl_expr.args[1].head == :call
            name = jl_expr.args[1].args[1]
            params = jl_expr.args[1].args[2:end]
        else
            jl_expr.args[1].head == :(::) || error("Invalid function defintion")
            returns = __parse_type(jl_expr.args[1].args[2])
            name = jl_expr.args[1].args[1].args[1]
            params = jl_expr.args[1].args[1].args[2:end]
        end

        arguments = __parse_args(params)
        body = __jl2py(jl_expr.args[2])
        if isempty(body)
            push!(body, AST.Pass())
        elseif !pyisinstance(body[end], AST.Return)
            if pyisinstance(body[end], AST.Assign)
                push!(body, AST.Return(body[end].targets[0]))
            elseif pyisinstance(body[end], AST.AugAssign)
                push!(body, AST.Return(body[end].target))
            elseif pyisinstance(body[end], AST.Expr)
                body[end] = AST.Return(body[end].value)
            elseif !pyisinstance(body[end], AST.For) && !pyisinstance(body[end], AST.While)
                body[end] = AST.Return(body[end])
            end
        end

        return AST.fix_missing_locations(AST.FunctionDef(pystr(name),
                                                         arguments,
                                                         PyList(body), PyList(); returns=returns))
    elseif jl_expr.head ∈ [:(&&), :(||)]
        __boolop(jl_expr, OP_DICT[jl_expr.head])
    elseif jl_expr.head == :tuple
        return AST.Tuple(__jl2py(jl_expr.args))
    elseif jl_expr.head == :...
        return AST.Starred(__jl2py(jl_expr.args[1]))
    elseif jl_expr.head == :.
        return AST.Attribute(__jl2py(jl_expr.args[1]), __jl2py(jl_expr.args[2]))
    elseif jl_expr.head == :->
        body = __jl2py(jl_expr.args[2])

        if isa(jl_expr.args[1], Expr) && jl_expr.args[1].head == :(::) && !isa(jl_expr.args[1].args[1], Symbol)
            jl_expr = jl_expr.args[1]
        end

        if isa(jl_expr.args[1], Symbol) || jl_expr.args[1].head == :(::)
            arguments = __parse_args([jl_expr.args[1]])
        else
            jl_expr.args[1].head == :tuple || error("Invalid lambda")
            arguments = __parse_args(jl_expr.args[1].args)
        end

        return AST.Lambda(arguments, body[end])
    elseif jl_expr.head ∈ [:if, :elseif]
        # Julia's `if` is always an expression, while Python's `if` is mostly a statement.
        test = __jl2py(jl_expr.args[1])
        if isa(jl_expr.args[2], Expr) && jl_expr.args[2].head == :block
            # AST.If
            body = __jl2py(jl_expr.args[2])
            orelse = length(jl_expr.args) == 3 ? __jl2py(jl_expr.args[3]) : nothing
            if !isnothing(orelse) && !isa(orelse, Vector)
                orelse = PyList([orelse])
            end
            return AST.If(test, body, orelse)
        else
            # AST.IfExp
            body = __jl2py(jl_expr.args[2])
            orelse = __jl2py(jl_expr.args[3])
            return AST.IfExp(test, body, orelse)
        end
    elseif jl_expr.head == :while
        test = __jl2py(jl_expr.args[1])
        body = __jl2py(jl_expr.args[2])
        return AST.While(test, body, nothing)
    elseif jl_expr.head == :for
        target = __jl2py(jl_expr.args[1].args[1])
        iter = __jl2py(jl_expr.args[1].args[2])
        body = __jl2py(jl_expr.args[2])
        return AST.fix_missing_locations(AST.For(target, iter, body, nothing, nothing))
    elseif jl_expr.head == :return
        value = __jl2py(jl_expr.args[1])
        return AST.Return(value)
    elseif jl_expr.head == :ref
        value = __jl2py(jl_expr.args[1])
        slices = map(jl_expr.args[2:end]) do arg
            if isa(arg, Expr) && arg.args[1] == :(:)
                slice = AST.Slice(__parse_range(arg.args[2:end])...)
            else
                slice = __jl2py(arg)
            end
        end
        slice = length(slices) == 1 ? slices[1] : AST.Tuple(PyList(slices))
        return AST.Subscript(value, slice)
    elseif jl_expr.head == :comprehension
        return AST.ListComp(__jl2py(jl_expr.args[1]; iscomprehension=true)...)
    elseif jl_expr.head == :generator
        if isflatten
            elt, extra_gens = __jl2py(jl_expr.args[1]; iscomprehension=iscomprehension)
            gens = __parse_generator(jl_expr.args[2:end])
            append!(gens, extra_gens)
        else
            elt = __jl2py(jl_expr.args[1])
            gens = __parse_generator(jl_expr.args[2:end])
        end
        return iscomprehension ? (elt, gens) : AST.GeneratorExp(elt, gens)
    elseif jl_expr.head == :filter
        filter = __jl2py(jl_expr.args[1])
        map(2:length(jl_expr.args)) do i
            arg = jl_expr.args[i]
            target = __jl2py(arg.args[1])
            iter = __jl2py(arg.args[2])
            return i == length(jl_expr.args) ? AST.comprehension(target, iter, PyList([filter]); is_async=false) :
                   AST.comprehension(target, iter, PyList(); is_async=false)
        end
    elseif jl_expr.head == :flatten
        return __jl2py(jl_expr.args[1]; isflatten=true, iscomprehension=iscomprehension)
    elseif jl_expr.head == :call
        if jl_expr.args[1] == :+
            if length(jl_expr.args) == 2
                __unaryop(jl_expr, OP_UDICT[jl_expr.args[1]])
            else
                __multiop(jl_expr, OP_DICT[jl_expr.args[1]])
            end
        elseif jl_expr.args[1] ∈ [:-, :~, :(!)]
            if length(jl_expr.args) == 2
                __unaryop(jl_expr, OP_UDICT[jl_expr.args[1]])
            else
                __binop(jl_expr, OP_DICT[jl_expr.args[1]])
            end
        elseif jl_expr.args[1] == :*
            __multiop(jl_expr, OP_DICT[jl_expr.args[1]])
        elseif jl_expr.args[1] == :(:)
            args = __parse_range(jl_expr.args[2:end])
            return AST.Call(AST.Name("range"), args, [])
        elseif jl_expr.args[1] ∈ [:/, :÷, :div, :%, :mod, :^, :&, :|, :⊻, :xor, :(<<), :(>>)]
            __binop(jl_expr, OP_DICT[jl_expr.args[1]])
        elseif jl_expr.args[1] ∈ [:(==), :(===), :≠, :(!=), :(!==), :<, :<=, :>, :>=, :∈, :∉, :in]
            __compareop_from_call(jl_expr, OP_DICT[jl_expr.args[1]])
        elseif jl_expr.args[1] == :(=>)
            return AST.Tuple(__jl2py(jl_expr.args[2:end]))
        elseif jl_expr.args[1] == :Dict ||
               (isa(jl_expr.args[1], Expr) && jl_expr.args[1].head == :curly && jl_expr.args[1].args[1] == :Dict)
            # Handle generator separately
            if length(jl_expr.args) == 2 && jl_expr.args[2].head == :generator
                generator = __jl2py(jl_expr.args[2])
                dict_call = AST.Call(AST.Name("dict"), PyList([generator]), PyList())
                return topofblock ? AST.Expr(dict_call) : dict_call
            end

            _keys = []
            values = []
            for arg in jl_expr.args[2:end]
                if isa(arg, Expr) && arg.head == :...
                    push!(_keys, nothing)
                    push!(values, __jl2py(arg.args[1]))
                else
                    key, value = __parse_pair(arg)
                    push!(_keys, key)
                    push!(values, value)
                end
            end
            return AST.fix_missing_locations(AST.Dict(PyList(_keys), PyList(values)))
        else
            if isa(jl_expr.args[1], Symbol) || jl_expr.args[1].head == :curly
                # We discard the curly braces trailing a function call
                arg = isa(jl_expr.args[1], Symbol) ? jl_expr.args[1] : jl_expr.args[1].args[1]
                if arg ∈ keys(BUILTIN_DICT)
                    func = AST.Name(BUILTIN_DICT[arg])
                elseif string(jl_expr.args[1])[end] != '!'
                    func = AST.Name(string(arg))
                else
                    func = AST.Name(string(arg)[1:(end - 1)] * "_inplace")
                end
            else
                func = __jl2py(jl_expr.args[1])
            end
            parameters = []
            keywords = []
            for arg in jl_expr.args[2:end]
                if isa(arg, Expr) && arg.head == :parameters
                    for param in arg.args
                        if param.head == :kw
                            key = pystr(param.args[1])
                            value = __jl2py(param.args[2])
                            push!(keywords, AST.keyword(key, value))
                        elseif param.head == :...
                            value = __jl2py(param.args[1])
                            push!(keywords, AST.keyword(nothing, value))
                        end
                    end
                else
                    push!(parameters, __jl2py(arg))
                end
            end

            call = AST.Call(func, parameters, keywords)
            return topofblock ? AST.Expr(call) : call
        end
    elseif jl_expr.head == :comparison
        __compareop_from_comparison(jl_expr)
    elseif jl_expr.head == :(=)
        # AnnAssign
        if isa(jl_expr.args[1], Expr) && jl_expr.args[1].head == :(::)
            target = __jl2py(jl_expr.args[1].args[1])
            annotation = __parse_type(jl_expr.args[1].args[2])
            value = __jl2py(jl_expr.args[2])
            return AST.fix_missing_locations(AST.AnnAssign(target, annotation, value, nothing))
        end

        # Assign
        targets = PyList()
        curr = jl_expr.args
        while isa(curr[2], Expr) && curr[2].head == :(=)
            push!(targets, __jl2py(curr[1]))
            curr = curr[2].args
        end
        last_target, value = __jl2py(curr)
        push!(targets, last_target)
        return AST.fix_missing_locations(AST.Assign(targets, value))
    elseif jl_expr.head ∈ [:+=, :-=, :*=, :/=, :÷=, :%=, :^=, :&=, :|=, :⊻=, :(<<=), :(>>=)]
        target = __jl2py(jl_expr.args[1])
        value = __jl2py(jl_expr.args[2])
        return AST.fix_missing_locations(AST.AugAssign(target, OP_DICT[jl_expr.head](), value))
    elseif jl_expr.head == :vect
        return AST.List(__jl2py(jl_expr.args))
    end
end

jl2py(ast) = __jl2py(ast)

function jl2py(jl_str::String; apply_polyfill::Bool=false)
    jl_ast = Meta.parse(jl_str)
    if isnothing(jl_ast)
        return ""
    end
    py_ast = __jl2py(jl_ast)
    _module = AST.Module(PyList([py_ast]), [])
    py_str = AST.unparse(_module)

    if apply_polyfill
        polyfill = read(joinpath(@__DIR__, "..", "polyfill", "polyfill.py"), String)
        return polyfill * "\n" * string(py_str)
    end

    return string(py_str)
end

function __init__()
    PythonCall.pycopy!(AST, pyimport("ast"))
    OP_UDICT[:+] = AST.UAdd
    OP_UDICT[:-] = AST.USub
    OP_UDICT[:~] = AST.Invert
    OP_UDICT[:(!)] = AST.Not

    OP_DICT[:+] = AST.Add
    OP_DICT[:-] = AST.Sub
    OP_DICT[:*] = AST.Mult
    OP_DICT[:/] = AST.Div
    OP_DICT[:÷] = AST.FloorDiv
    OP_DICT[:div] = AST.FloorDiv
    OP_DICT[:%] = AST.Mod
    OP_DICT[:mod] = AST.Mod
    OP_DICT[:^] = AST.Pow
    OP_DICT[:(==)] = AST.Eq
    OP_DICT[:(===)] = AST.Eq
    OP_DICT[:≠] = AST.NotEq
    OP_DICT[:(!=)] = AST.NotEq
    OP_DICT[:(!==)] = AST.NotEq
    OP_DICT[:<] = AST.Lt
    OP_DICT[:<=] = AST.LtE
    OP_DICT[:>=] = AST.GtE
    OP_DICT[:>] = AST.Gt
    OP_DICT[:in] = AST.In
    OP_DICT[:∈] = AST.In
    OP_DICT[:∉] = AST.NotIn
    OP_DICT[:(<<)] = AST.LShift
    OP_DICT[:(>>)] = AST.RShift
    OP_DICT[:&] = AST.BitAnd
    OP_DICT[:|] = AST.BitOr
    OP_DICT[:⊻] = AST.BitXor
    OP_DICT[:xor] = AST.BitXor
    OP_DICT[:(&&)] = AST.And
    OP_DICT[:(||)] = AST.Or
    OP_DICT[:+=] = AST.Add
    OP_DICT[:-=] = AST.Sub
    OP_DICT[:*=] = AST.Mult
    OP_DICT[:/=] = AST.Div
    OP_DICT[:÷=] = AST.FloorDiv
    OP_DICT[:%=] = AST.Mod
    OP_DICT[:^=] = AST.Pow
    OP_DICT[:(<<=)] = AST.LShift
    OP_DICT[:(>>=)] = AST.RShift
    OP_DICT[:&=] = AST.BitAnd
    OP_DICT[:|=] = AST.BitOr
    OP_DICT[:⊻=] = AST.BitXor

    TYPE_DICT[:Float32] = "float"
    TYPE_DICT[:Float64] = "float"
    TYPE_DICT[:Int] = "int"
    TYPE_DICT[:Int8] = "int"
    TYPE_DICT[:Int16] = "int"
    TYPE_DICT[:Int32] = "int"
    TYPE_DICT[:Int64] = "int"
    TYPE_DICT[:Int128] = "int"
    TYPE_DICT[:UInt] = "int"
    TYPE_DICT[:UInt8] = "int"
    TYPE_DICT[:UInt16] = "int"
    TYPE_DICT[:UInt32] = "int"
    TYPE_DICT[:UInt64] = "int"
    TYPE_DICT[:UInt128] = "int"
    TYPE_DICT[:Bool] = "bool"
    TYPE_DICT[:Char] = "str"
    TYPE_DICT[:String] = "str"
    TYPE_DICT[:Vector] = "List"
    TYPE_DICT[:Set] = "Set"
    TYPE_DICT[:Dict] = "Dict"
    TYPE_DICT[:Tuple] = "Tuple"
    TYPE_DICT[:Pair] = "Tuple"
    TYPE_DICT[:Union] = "Union"
    TYPE_DICT[:Nothing] = "None"

    BUILTIN_DICT[:length] = "len"
    BUILTIN_DICT[:sort] = "sorted"
    BUILTIN_DICT[:print] = "print"
    BUILTIN_DICT[:println] = "print"
    BUILTIN_DICT[:Set] = "set"

    return
end

end
