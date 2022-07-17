module Jl2Py

export jl2py

using PythonCall

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

const AST = PythonCall.pynew()
const OP_DICT = Dict{Symbol,Py}()
const OP_UDICT = Dict{Symbol,Py}()
const TYPE_DICT = Dict{Symbol,String}()

function __parse_arg(expr::Union{Symbol,Expr})
    if isa(expr, Symbol)
        return AST.arg(pystr(expr))
    else
        expr.head == :(::) || error("Invalid arg expr")
        return AST.arg(pystr(expr.args[1]), AST.Name(pystr(TYPE_DICT[expr.args[2]])))
    end
end

function __parse_pair(expr::Expr)
    (expr.head == :call && expr.args[1] == :(=>)) || error("Invalid pair expr")
    return __jl2py(expr.args[2]), __jl2py(expr.args[3])
end

function __jl2py(args::AbstractVector)
    return map(__jl2py, args)
end

function __jl2py(jl_constant::Union{Number,String})
    return AST.Constant(jl_constant)
end

function __jl2py(jl_symbol::Symbol)
    return AST.Name(pystr(jl_symbol))
end

function __jl2py(jl_expr::Expr; topofblock::Bool=false)
    if jl_expr.head ∈ [:block, :toplevel]
        py_exprs = [__jl2py(expr; topofblock=true) for expr in jl_expr.args if !isa(expr, LineNumberNode)]
        return PyList(py_exprs)
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
        return AST.fix_missing_locations(AST.FunctionDef(pystr(name),
                                                         AST.arguments(; args=PyList(args), posonlyargs=PyList(),
                                                                       kwonlyargs=PyList(), defaults=PyList()),
                                                         PyList(body), PyList(), PyList()))
    elseif jl_expr.head ∈ [:(&&), :(||)]
        __boolop(jl_expr, OP_DICT[jl_expr.head])
    elseif jl_expr.head == :tuple
        return AST.Tuple(__jl2py(jl_expr.args))
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
            args = __jl2py(jl_expr.args[2:end])
            if length(args) == 2
                return AST.Call(AST.Name("range"), args, [])
            elseif length(args) == 3
                return AST.Call(AST.Name("range"), [args[1], args[3], args[2]], [])
            end
        elseif jl_expr.args[1] ∈ [:/, :÷, :div, :%, :mod, :^, :&, :|, :⊻, :xor, :(<<), :(>>)]
            __binop(jl_expr, OP_DICT[jl_expr.args[1]])
        elseif jl_expr.args[1] ∈ [:(==), :(===), :≠, :(!=), :(!==), :<, :<=, :>, :>=]
            __compareop_from_call(jl_expr, OP_DICT[jl_expr.args[1]])
        elseif jl_expr.args[1] == :Set ||
               (isa(jl_expr.args[1], Expr) && jl_expr.args[1].head == :curly && jl_expr.args[1].args[1] == :Set)
            keys = __jl2py(jl_expr.args[2:end])
            return AST.fix_missing_locations(AST.Set(PyList(keys)))
        elseif jl_expr.args[1] == :Dict ||
               (isa(jl_expr.args[1], Expr) && jl_expr.args[1].head == :curly && jl_expr.args[1].args[1] == :Dict)
            keys = []
            values = []
            for arg in jl_expr.args[2:end]
                key, value = __parse_pair(arg)
                push!(keys, key)
                push!(values, value)
            end
            return AST.fix_missing_locations(AST.Dict(PyList(keys), PyList(values)))
        else
            # TODO: handle keyword arguments
            func = __jl2py(jl_expr.args[1])
            parameters = __jl2py(jl_expr.args[2:end])
            call = AST.Call(func, parameters, [])
            return topofblock ? AST.Expr(call) : call
        end
    elseif jl_expr.head == :comparison
        __compareop_from_comparison(jl_expr)
    elseif jl_expr.head == :(=)
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
        listop = AST.List(__jl2py(jl_expr.args))
        return listop
    end
end

function jl2py(jl_str::String)
    jl_ast = Meta.parse(jl_str)
    py_ast = __jl2py(jl_ast)
    _module = AST.Module(PyList([py_ast]), [])
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

    return
end

end
