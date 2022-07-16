module Jl2Py

export jl2py

using PythonCall

macro __unaryop(jl_expr, op)
    quote
        operand = __jl2py($(esc(jl_expr)).args[2])
        if isa(operand, Vector)
            operand = operand[1]
        end
        unaryop = AST.UnaryOp($op(), operand)
        return [unaryop]
    end
end

macro __binop(jl_expr, op)
    quote
        jl_expr = $(esc(jl_expr))
        left = __jl2py(jl_expr.args[2])
        if isa(left, Vector)
            left = left[1]
        end
        right = __jl2py(jl_expr.args[3])
        if isa(right, Vector)
            right = right[1]
        end
        binop = AST.BinOp(left, $op(), right)
        return [binop]
    end
end

macro __compareop_from_comparison(jl_expr)
    quote
        jl_expr = $(esc(jl_expr))
        elts = __jl2py(jl_expr.args[1:2:end])
        ops = map(x -> OP_DICT[x](), jl_expr.args[2:2:end])
        compareop = AST.Compare(elts[1], ops, elts[2:end])
        return [compareop]
    end
end

macro __compareop_from_call(jl_expr, op)
    quote
        jl_expr = $(esc(jl_expr))
        elts = __jl2py(jl_expr.args[2:end])
        compareop = AST.Compare(elts[1], [$op()], elts[2:end])
        return [compareop]
    end
end

macro __multiop(jl_expr, op)
    quote
        jl_expr = $(esc(jl_expr))
        left = __jl2py(jl_expr.args[2])
        if isa(left, Vector)
            left = left[1]
        end
        right = __jl2py(jl_expr.args[3])
        if isa(right, Vector)
            right = right[1]
        end
        binop = AST.BinOp(left, $op(), right)
        argcnt = length(jl_expr.args)
        for i in 4:argcnt
            right = __jl2py(jl_expr.args[i])
            if isa(right, Vector)
                right = right[1]
            end
            binop = AST.BinOp(binop, $op(), right)
        end
        return [binop]
    end
end

const AST = PythonCall.pynew()
const OP_DICT = Dict{Symbol,Py}()

function __jl2py(args::AbstractVector)
    return map(x -> isa(x, Vector) ? x[1] : x, map(__jl2py, args))
end

function __jl2py(jl_constant::Union{Number,String})
    return AST.Constant(jl_constant)
end

function __jl2py(jl_symbol::Symbol)
    return AST.Name(pystr(jl_symbol))
end

function __jl2py(jl_expr::Expr)
    if jl_expr.head == :block || jl_expr.head == :toplevel
        py_exprs = []
        for expr in jl_expr.args
            if isa(expr, LineNumberNode)
                continue
            end

            py_expr = __jl2py(expr)
            if isa(py_expr, Vector)
                append!(py_exprs, py_expr)
            else
                push!(py_exprs, AST.Expr(py_expr))
            end
        end

        return py_exprs
    elseif jl_expr.head == :call
        if jl_expr.args[1] == :+
            if length(jl_expr.args) == 2
                @__unaryop(jl_expr, AST.UAdd)
            else
                @__multiop(jl_expr, OP_DICT[jl_expr.args[1]])
            end
        elseif jl_expr.args[1] == :-
            if length(jl_expr.args) == 2
                @__unaryop(jl_expr, AST.USub)
            else
                @__binop(jl_expr, OP_DICT[jl_expr.args[1]])
            end
        elseif jl_expr.args[1] == :*
            @__multiop(jl_expr, OP_DICT[jl_expr.args[1]])
        elseif jl_expr.args[1] ∈ [:/, :÷, :div, :%, :mod, :^]
            @__binop(jl_expr, OP_DICT[jl_expr.args[1]])
        elseif jl_expr.args[1] ∈ [:(==), :(===), :≠, :(!=), :(!==), :<, :<=, :>, :>=]
            @__compareop_from_call(jl_expr, OP_DICT[jl_expr.args[1]])
        else
            # FIXME: handle keyword arguments
            func = __jl2py(jl_expr.args[1])
            parameters = __jl2py(jl_expr.args[2:end])
            call = AST.Call(func, parameters, [])
            return [AST.Expr(call)]
        end
    elseif jl_expr.head == :comparison
        @__compareop_from_comparison(jl_expr)
    elseif jl_expr.head == :(=)
        targets = PyList()
        curr = jl_expr.args
        while isa(curr[2], Expr) && curr[2].head == :(=)
            push!(targets, __jl2py(curr[1]))
            curr = curr[2].args
        end
        last_target, value = __jl2py(curr)
        push!(targets, last_target)
        return [AST.fix_missing_locations(AST.Assign(targets, value))]
    elseif jl_expr.head == :vect
        listop = AST.List(__jl2py(jl_expr.args))
        return [listop]
    else
        return []
    end
end

function jl2py(jl_str::String)
    jl_ast = Meta.parse(jl_str)
    py_body = PyList()

    if isa(jl_ast, Union{Number,String,Symbol})
        push!(py_body, __jl2py(jl_ast))
    elseif isa(jl_ast, Expr)
        append!(py_body, __jl2py(jl_ast))
    end

    _module = AST.Module(py_body, [])
    py_str = AST.unparse(_module)
    return string(py_str)
end

function __init__()
    PythonCall.pycopy!(AST, pyimport("ast"))
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
end

end
