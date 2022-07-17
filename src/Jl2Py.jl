module Jl2Py

export jl2py

using PythonCall

macro __unaryop(jl_expr, op)
    quote
        jl_expr = $(esc(jl_expr))
        operand = __jl2py(jl_expr.args[2])
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

macro __boolop(jl_expr, op)
    quote
        jl_expr = $(esc(jl_expr))
        left = __jl2py(jl_expr.args[1])
        if isa(left, Vector)
            left = left[1]
        end
        right = __jl2py(jl_expr.args[2])
        if isa(right, Vector)
            right = right[1]
        end
        boolop = AST.BoolOp($op(), [left, right])
        return [boolop]
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
const OP_UDICT = Dict{Symbol,Py}()
const TYPE_DICT = Dict{Symbol,String}()

function __parse_arg(sym::Symbol)
    return AST.arg(pystr(sym))
end

function __parse_arg(expr::Expr)
    expr.head == :(::) || error("Invalid arg expr")
    return AST.arg(pystr(expr.args[1]), AST.Name(pystr(TYPE_DICT[expr.args[2]])))
end

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
    if jl_expr.head ∈ [:block, :toplevel]
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
    elseif jl_expr.head == :function
        name = jl_expr.args[1].args[1]
        args = map(__parse_arg, jl_expr.args[1].args[2:end])
        body = __jl2py(jl_expr.args[2])
        if isempty(body)
            push!(body, AST.Pass())
        elseif !pyis(body[end], AST.Return)
            body[end] = AST.Return(body[end])
        end

        # TODO: handle various arguments
        return [AST.fix_missing_locations(AST.FunctionDef(pystr(name),
                                                          AST.arguments(; args=PyList(args), posonlyargs=PyList(),
                                                                        kwonlyargs=PyList(), defaults=PyList()),
                                                          PyList(body), PyList(), PyList()))]
    elseif jl_expr.head ∈ [:(&&), :(||)]
        @__boolop(jl_expr, OP_DICT[jl_expr.head])
    elseif jl_expr.head == :call
        if jl_expr.args[1] == :+
            if length(jl_expr.args) == 2
                @__unaryop(jl_expr, OP_UDICT[jl_expr.args[1]])
            else
                @__multiop(jl_expr, OP_DICT[jl_expr.args[1]])
            end
        elseif jl_expr.args[1] ∈ [:-, :~, :(!)]
            if length(jl_expr.args) == 2
                @__unaryop(jl_expr, OP_UDICT[jl_expr.args[1]])
            else
                @__binop(jl_expr, OP_DICT[jl_expr.args[1]])
            end
        elseif jl_expr.args[1] == :*
            @__multiop(jl_expr, OP_DICT[jl_expr.args[1]])
        elseif jl_expr.args[1] == :(:)
            args = __jl2py(jl_expr.args[2:end])
            if length(args) == 2
                return [AST.Call(AST.Name("range"), args, [])]
            elseif length(args) == 3
                return [AST.Call(AST.Name("range"), [args[1], args[3], args[2]], [])]
            end
        elseif jl_expr.args[1] ∈ [:/, :÷, :div, :%, :mod, :^, :&, :|, :⊻, :xor, :(<<), :(>>)]
            @__binop(jl_expr, OP_DICT[jl_expr.args[1]])
        elseif jl_expr.args[1] ∈ [:(==), :(===), :≠, :(!=), :(!==), :<, :<=, :>, :>=]
            @__compareop_from_call(jl_expr, OP_DICT[jl_expr.args[1]])
        else
            # TODO: handle keyword arguments
            func = __jl2py(jl_expr.args[1])
            parameters = __jl2py(jl_expr.args[2:end])
            call = AST.Call(func, parameters, [])
            return [call]
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

    TYPE_DICT[:Float64] = "float"
    TYPE_DICT[:Int64] = "int"
    TYPE_DICT[:Bool] = "bool"
    TYPE_DICT[:String] = "str"

    return
end

end
