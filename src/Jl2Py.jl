module Jl2Py

export jl2py, unparse

using MLStyle
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
    @match args begin
        [start::Integer, stop::Integer] => [AST.Constant(start), AST.Constant(stop + 1)]
        [start, stop] => [__jl2py(start), AST.BinOp(__jl2py(stop), AST.Add(), AST.Constant(1))]
        [start::Integer, step::Integer, stop::Integer] => [AST.Constant(start), AST.Constant(stop + sign(step)),
                                                           __jl2py(step)]
        [start, step, stop] => [__jl2py(start), __jl2py(stop), __jl2py(step)]
    end
end

function __parse_type(typ::Union{Symbol,Expr})
    @match typ begin
        ::Symbol => AST.Name(get(TYPE_DICT, typ, pystr(typ)))
        Expr(:curly, arg1, arg2) => AST.Subscript(__parse_type(arg1), __parse_type(arg2))
        Expr(:curly, arg1, args...) => AST.Subscript(__parse_type(arg1), AST.Tuple(map(__parse_type, args)))
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

function __parse_if(expr::Expr)
    # Julia's `if` is always an expression, while Python's `if` is mostly a statement.
    test = __jl2py(expr.args[1])
    @match expr.args[2] begin
        Expr(:block, _...) => begin
            # AST.If
            body = __jl2py(expr.args[2])
            orelse = length(expr.args) == 3 ? __jl2py(expr.args[3]) : nothing
            if !isnothing(orelse) && !isa(orelse, Vector)
                orelse = PyList([orelse])
            end
            AST.If(test, body, orelse)
        end
        _ => begin
            # AST.IfExp
            body = __jl2py(expr.args[2])
            orelse = __jl2py(expr.args[3])
            AST.IfExp(test, body, orelse)
        end
    end
end

function __parse_function(expr::Expr)
    returns = nothing
    if expr.args[1].head == :call
        name = expr.args[1].args[1]
        params = expr.args[1].args[2:end]
    elseif expr.args[1].head == :(::)
        returns = __parse_type(expr.args[1].args[2])
        name = expr.args[1].args[1].args[1]
        params = expr.args[1].args[1].args[2:end]
    else
        expr.head = :-> # Assume it to be a lambda
        return __jl2py(expr)
    end

    arguments = __parse_args(params)

    # # The following code tries to handle return issue in Julia
    # # but still has some issues.
    #
    # i = lastindex(jl_expr.args[2].args)
    # while i > 0 && isa(jl_expr.args[2].args[i], LineNumberNode)
    #     i -= 1
    # end
    # if i > 0
    #     last_arg = jl_expr.args[2].args[i]
    #     if !(isa(last_arg, Expr) && last_arg.head == :return)
    #         jl_expr.args[2].args[i] = Expr(:return, last_arg)
    #     end
    # end

    body = __jl2py(expr.args[2])
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
end

function __parse_lambda(expr::Expr)
    begin
        body = __jl2py(expr.args[2])

        if isa(expr.args[1], Expr) && expr.args[1].head == :(::) && !isa(expr.args[1].args[1], Symbol)
            expr = expr.args[1]
        end

        if isa(expr.args[1], Symbol) || expr.args[1].head == :(::)
            arguments = __parse_args([expr.args[1]])
        else
            map!(expr.args[1].args, expr.args[1].args) do arg
                return isa(arg, Expr) && arg.head == :(=) ? Expr(:kw, arg.args[1], arg.args[2]) : arg
            end

            if expr.args[1].head == :tuple
                arguments = __parse_args(expr.args[1].args)
            else
                expr.args[1].head == :block || error("Invalid lambda")
                split_pos = findfirst(x -> isa(x, LineNumberNode), expr.args[1].args)
                wrapped_args = expr.args[1].args[1:(split_pos - 1)]
                keyword_args = Expr(:parameters,
                                    map(expr.args[1].args[(split_pos + 1):end]) do arg
                                        return arg.head == :(=) ? Expr(:kw, arg.args[1], arg.args[2]) : arg
                                    end...)
                push!(wrapped_args, keyword_args)
                arguments = __parse_args(wrapped_args)
            end
        end

        length(body) >= 2 && error("Python lambdas can only have one statement.")

        # # Use a hacky way to compress all lines of body into one line
        # if length(body) > 1
        #     prev = map(x -> AST.BoolOp(AST.And(), [x, AST.Constant(false)]), body[1:(end - 1)])
        #     body = AST.BoolOp(AST.Or(), PyList([prev..., body[end]]))
        # else
        #     body = body[1]
        # end

        return AST.Lambda(arguments, body[1])
    end
end

function __parse_ref(value, slices)
    value = __jl2py(value)
    map!(slices, slices) do arg
        if isa(arg, Expr) && arg.args[1] == :(:)
            slice = AST.Slice(__parse_range(arg.args[2:end])...)
        else
            slice = __jl2py(arg)
        end
    end
    slice = length(slices) == 1 ? slices[1] : AST.Tuple(PyList(slices))
    return AST.Subscript(value, slice)
end

function __parse_generator(arg1, args; isflatten, iscomprehension)
    if isflatten
        elt, extra_gens = __jl2py(arg1; iscomprehension=iscomprehension)
        gens = __parse_generator(args)
        append!(gens, extra_gens)
    else
        elt = __jl2py(arg1)
        gens = __parse_generator(args)
    end
    return iscomprehension ? (elt, gens) : AST.GeneratorExp(elt, gens)
end

function __parse_filter(filter, args)
    filter = __jl2py(filter)
    return map(1:length(args)) do i
        arg = args[i]
        target = __jl2py(arg.args[1])
        iter = __jl2py(arg.args[2])
        return i == length(args) ? AST.comprehension(target, iter, PyList([filter]); is_async=false) :
               AST.comprehension(target, iter, PyList(); is_async=false)
    end
end

function __parse_call(jl_expr, arg1, args; topofblock)
    if arg1 == :+
        if length(args) == 1
            __unaryop(jl_expr, OP_UDICT[arg1])
        else
            __multiop(jl_expr, OP_DICT[arg1])
        end
    elseif arg1 ∈ [:-, :~, :(!)]
        if length(args) == 1
            __unaryop(jl_expr, OP_UDICT[arg1])
        else
            __binop(jl_expr, OP_DICT[arg1])
        end
    elseif arg1 == :*
        __multiop(jl_expr, OP_DICT[arg1])
    elseif arg1 == :(:)
        AST.Call(AST.Name("range"), __parse_range(args), [])
    elseif arg1 ∈ [:/, :÷, :div, :%, :mod, :^, :&, :|, :⊻, :xor, :(<<), :(>>)]
        __binop(jl_expr, OP_DICT[arg1])
    elseif arg1 ∈ [:(==), :(===), :≠, :(!=), :(!==), :<, :<=, :>, :>=, :∈, :∉, :in]
        __compareop_from_call(jl_expr, OP_DICT[arg1])
    elseif arg1 == :(=>)
        AST.Tuple(__jl2py(args))
    elseif arg1 == :Dict ||
           (isa(arg1, Expr) && arg1.head == :curly && arg1.args[1] == :Dict)
        # Handle generator separately
        if length(args) == 1 && args[1].head == :generator
            generator = __jl2py(args[1])
            dict_call = AST.Call(AST.Name("dict"), PyList([generator]), PyList())
            return topofblock ? AST.Expr(dict_call) : dict_call
        end

        _keys = []
        values = []
        for arg in args
            if isa(arg, Expr) && arg.head == :...
                push!(_keys, nothing)
                push!(values, __jl2py(arg.args[1]))
            else
                key, value = __parse_pair(arg)
                push!(_keys, key)
                push!(values, value)
            end
        end

        AST.fix_missing_locations(AST.Dict(PyList(_keys), PyList(values)))
    else
        if isa(arg1, Symbol) || arg1.head == :curly
            # We discard the curly braces trailing a function call
            arg = isa(arg1, Symbol) ? arg1 : arg1.args[1]
            if arg ∈ keys(BUILTIN_DICT)
                func = AST.Name(BUILTIN_DICT[arg])
            elseif string(arg1)[end] != '!'
                func = AST.Name(string(arg))
            else
                func = AST.Name(string(arg)[1:(end - 1)] * "_inplace")
            end
        else
            func = __jl2py(arg1)
        end
        parameters = []
        keywords = []
        for arg in args
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
        topofblock ? AST.Expr(call) : call
    end
end

function __parse_assign(args)
    @match args[1] begin
        Expr(:(::), target, annotation) => AST.fix_missing_locations(AST.AnnAssign(__jl2py(target),
                                                                                   __parse_type(annotation),
                                                                                   __jl2py(args[2]), nothing)) # AnnAssign
        _ => begin # Assign
            targets = PyList()
            curr = args
            while isa(curr[2], Expr) && curr[2].head == :(=)
                push!(targets, __jl2py(curr[1]))
                curr = curr[2].args
            end
            last_target, value = __jl2py(curr)
            push!(targets, last_target)
            return AST.fix_missing_locations(AST.Assign(targets, value))
        end
    end
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

__jl2py(::Nothing) = AST.Constant(nothing)

function __jl2py(jl_expr::Expr; topofblock::Bool=false, isflatten::Bool=false, iscomprehension::Bool=false)
    @match jl_expr begin
        Expr(:block, args...) ||
        Expr(:toplevel, args...) => PyList([__jl2py(expr; topofblock=true)
                                            for expr in args if !isa(expr, LineNumberNode)])
        Expr(:function, _...) => __parse_function(jl_expr)
        Expr(:(&&), _...) ||
        Expr(:(||), _...) => __boolop(jl_expr, OP_DICT[jl_expr.head])
        Expr(:tuple, args...) => AST.Tuple(__jl2py(jl_expr.args))
        Expr(:..., arg) => AST.Starred(__jl2py(arg))
        Expr(:., arg1, arg2) => AST.Attribute(__jl2py(arg1), __jl2py(arg2))
        Expr(:->, _...) => __parse_lambda(jl_expr)
        Expr(:if, _...) || Expr(:elseif, _...) => __parse_if(jl_expr)
        Expr(:while, test, body) => AST.While(__jl2py(test), __jl2py(body), nothing)
        Expr(:for, Expr(_, target, iter), body) => AST.fix_missing_locations(AST.For(__jl2py(target), __jl2py(iter),
                                                                                     __jl2py(body), nothing, nothing))
        Expr(:continue) => AST.Continue()
        Expr(:break) => AST.Break()
        Expr(:return, arg) => AST.Return(__jl2py(arg))
        Expr(:ref, value, slices...) => __parse_ref(value, slices)
        Expr(:comprehension, arg) => AST.ListComp(__jl2py(arg; iscomprehension=true)...)
        Expr(:generator, arg1, args...) => __parse_generator(arg1, args; isflatten, iscomprehension)
        Expr(:filter, filter, args...) => __parse_filter(filter, args)
        Expr(:flatten, arg) => __jl2py(arg; isflatten=true, iscomprehension=iscomprehension)
        Expr(:comparison, _...) => __compareop_from_comparison(jl_expr)
        Expr(:call, arg1, args...) => __parse_call(jl_expr, arg1, args; topofblock)
        Expr(:(=), args...) => __parse_assign(args)
        Expr(:vect, args...) => AST.List(__jl2py(args))
        Expr(op, target, value) => AST.fix_missing_locations(AST.AugAssign(__jl2py(target),
                                                                           OP_DICT[op](),
                                                                           __jl2py(value)))
        _ => begin
            @warn("Pattern unmatched")
            return AST.Constant(nothing)
        end
    end
end

jl2py(ast) = __jl2py(ast)
unparse(ast) = AST.unparse(ast)

function jl2py(jl_str::String; ast_only::Bool=false, apply_polyfill::Bool=false)
    jl_ast = Meta.parse(jl_str)
    if isnothing(jl_ast)
        return ""
    end
    py_ast = __jl2py(jl_ast)

    if ast_only
        return py_ast
    end

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
