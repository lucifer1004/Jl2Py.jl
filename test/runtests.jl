using Jl2Py
using PythonCall
using Test

@testset "Jl2Py.jl" begin
    @testset "Basic functions" begin
        @testset "Empty" begin
            @test jl2py("") == ""
            @test jl2py("#comment") == ""
        end

        @testset "Literal constants" begin
            @test jl2py("2") == "2"
            @test jl2py("2.0") == "2.0"
            @test jl2py("\"hello\"") == "'hello'"
            @test jl2py("false") == "False"
            @test jl2py("true") == "True"
            @test jl2py("nothing") == "None"
            @test jl2py("foo") == "foo"
        end

        @testset "Attributes" begin
            @test jl2py("a.b") == "a.b"
            @test jl2py("a.b.c") == "a.b.c"
            @test jl2py("a.b.c.d") == "a.b.c.d"
        end

        @testset "UAdd & USub" begin
            @test jl2py("+3") == "3"
            @test jl2py("-3") == "-3"
            @test jl2py("+a") == "+a"
            @test jl2py("-a") == "-a"
        end

        @testset "Add" begin
            @test jl2py("1 + 1") == "1 + 1"
            @test jl2py("1 + 1 + 1") == "1 + 1 + 1"
            @test jl2py("1 + 1 + 1 + 1") == "1 + 1 + 1 + 1"
            @test jl2py("a + 2") == "a + 2"
            @test jl2py("a + b") == "a + b"
        end

        @testset "Sub" begin
            @test jl2py("1 - 1") == "1 - 1"
            @test jl2py("a - 2") == "a - 2"
            @test jl2py("a - b") == "a - b"
        end

        @testset "Mult" begin
            @test jl2py("1 * 2") == "1 * 2"
            @test jl2py("1 * 2 * 3") == "1 * 2 * 3"
        end

        @testset "Div & FloorDiv" begin
            @test jl2py("1 / 2") == "1 / 2"
            @test jl2py("1 ÷ 3") == "1 // 3"
            @test jl2py("div(3, 1)") == "3 // 1"
        end

        @testset "Mod" begin
            @test jl2py("1 % 2") == "1 % 2"
            @test jl2py("mod(3, 1)") == "3 % 1"
        end

        @testset "Pow" begin
            @test jl2py("10 ^ 5") == "10 ** 5"
        end

        @testset "Bitwise operators" begin
            @test jl2py("~2") == "~2"
            @test jl2py("1 & 2") == "1 & 2"
            @test jl2py("1 | 2") == "1 | 2"
            @test jl2py("1 ⊻ 2") == "1 ^ 2"
            @test jl2py("xor(1, 2)") == "1 ^ 2"
            @test jl2py("1 << 2") == "1 << 2"
            @test jl2py("1 >> 2") == "1 >> 2"
            @test jl2py("1 + (-2 * 6) >> 2") == "1 + (-2 * 6 >> 2)" # Note the different association order
        end

        @testset "Logical operators" begin
            @test jl2py("!true") == "not True"
            @test jl2py("!false") == "not False"
            @test jl2py("!a") == "not a"
            @test jl2py("true && false") == "True and False"
            @test jl2py("true || false") == "True or False"
        end

        @testset "Complex arithmetic" begin
            @test jl2py("(1 + 5) * (2 - 5) / (3 * 6)") == "(1 + 5) * (2 - 5) / (3 * 6)"
        end

        @testset "Binary comparisons" begin
            @test jl2py("1 == 2") == "1 == 2"
            @test jl2py("1 === 2") == "1 == 2"
            @test jl2py("1 != 2") == "1 != 2"
            @test jl2py("1 < 2") == "1 < 2"
            @test jl2py("1 <= 2") == "1 <= 2"
            @test jl2py("1 > 2") == "1 > 2"
            @test jl2py("1 >= 2") == "1 >= 2"
            @test jl2py("a ∈ b") == "a in b"
            @test jl2py("a in b") == "a in b"
            @test jl2py("a ∉ b") == "a not in b"
        end

        @testset "Multiple comparisons" begin
            @test jl2py("1 < 2 < 3") == "1 < 2 < 3"
            @test jl2py("1 < 2 < 3 < 4") == "1 < 2 < 3 < 4"
            @test jl2py("3 > 2 != 3 == 3") == "3 > 2 != 3 == 3"
        end

        @testset "Ternary operator" begin
            @test jl2py("x > 2 ? 1 : 0") == "1 if x > 2 else 0"
        end

        @testset "Ranges" begin
            @test jl2py("1:10") == "range(1, 11)"
            @test jl2py("1:2:10") == "range(1, 11, 2)"
            @test jl2py("a:b") == "range(a, b + 1)"
            @test jl2py("1:0.1:5") == "range(1, 5, 0.1)"
        end

        @testset "List" begin
            @test jl2py("[1, 2, 3]") == "[1, 2, 3]"
            @test jl2py("[1, 2 + 3, 3]") == "[1, 2 + 3, 3]"
            @test jl2py("[1, 2, [3, 4], []]") == "[1, 2, [3, 4], []]"
        end

        @testset "Pair" begin
            @test jl2py("1 => 2") == "(1, 2)"
            @test jl2py("a => b") == "(a, b)"
            @test jl2py("a => b => c") == "(a, (b, c))"
        end

        @testset "Tuple" begin
            @test jl2py("(1,)") == "(1,)"
            @test jl2py("(1, 2, 3)") == "(1, 2, 3)"
            @test jl2py("(1, 2, 3,)") == "(1, 2, 3)"
            @test jl2py("(a, a + b, c)") == "(a, a + b, c)"
        end

        @testset "Dict" begin
            @test jl2py("Dict(1=>2, 3=>14)") == "{1: 2, 3: 14}"
            @test jl2py("Dict{Number,Number}(1=>2, 3=>14)") == "{1: 2, 3: 14}" # Type info is discarded
        end

        @testset "Expansion" begin
            @test jl2py("(a...,)") == "(*a,)"
            @test jl2py("[a..., b...]") == "[*a, *b]"
            @test jl2py("Dict(a..., b => c)") == "{**a, b: c}"
        end

        @testset "Assign" begin
            @test jl2py("a = 2") == "a = 2"
            @test jl2py("a = 2 + 3") == "a = 2 + 3"
            @test jl2py("a = b = 2") == "a = b = 2"
            @test jl2py("a = b = c = 23 + 3") == "a = b = c = 23 + 3"
        end

        @testset "AnnAssign" begin
            @test jl2py("a::Int = 2") == "(a): int = 2"
        end

        @testset "AugAssign" begin
            @test jl2py("a += 2") == "a += 2"
            @test jl2py("a -= 2 + 3") == "a -= 2 + 3"
            @test jl2py("a *= 2") == "a *= 2"
            @test jl2py("a /= 2") == "a /= 2"
            @test jl2py("a ÷= 2") == "a //= 2"
            @test jl2py("a %= 2") == "a %= 2"
            @test jl2py("a ^= 2") == "a **= 2"
            @test jl2py("a <<= 2") == "a <<= 2"
            @test jl2py("a >>= 2") == "a >>= 2"
            @test jl2py("a &= 2") == "a &= 2"
            @test jl2py("a |= 2") == "a |= 2"
            @test jl2py("a ⊻= 2") == "a ^= 2"
        end

        @testset "If statement" begin
            @test jl2py("if x > 3 x += 2 end") == "if x > 3:\n    x += 2"
            @test jl2py("if x > 3 x += 2 else x -= 1 end") == "if x > 3:\n    x += 2\nelse:\n    x -= 1"
            @test jl2py("if x > 3 x += 2 elseif x < 0 x -= 1 end") ==
                  "if x > 3:\n    x += 2\nelif x < 0:\n    x -= 1"
        end

        @testset "While statement" begin
            @test jl2py("while x > 3 x -= 1 end") == "while x > 3:\n    x -= 1"
        end

        @testset "For statement" begin
            @test jl2py("for (x, y) in zip(a, b) print(x) end") ==
                  "for (x, y) in zip(a, b):\n    print(x)"
        end

        @testset "Subscript" begin
            @test jl2py("a[1]") == "a[1]"
            @test jl2py("a[1:5]") == "a[1:6]"
            @test jl2py("a[1:2:5]") == "a[1:6:2]"
            @test jl2py("a[1,2,3]") == "a[1, 2, 3]"
            @test jl2py("a[1,2:5,3]") == "a[1, 2:6, 3]"
            @test jl2py("a[:,1,2:4]") == "a[:, 1, 2:5]"
            @test jl2py("d[\"a\"]") == "d['a']"
        end

        @testset "GeneratorExp" begin
            @test jl2py("sum(x for x in 1:100)") == "sum((x for x in range(1, 101)))"
            @test jl2py("Set(x for x in 1:100)") == "set((x for x in range(1, 101)))"
            @test jl2py("Dict(x=>y for (x, y) in zip(1:5, 1:6))") ==
                  "dict(((x, y) for (x, y) in zip(range(1, 6), range(1, 7))))"
        end

        @testset "List Comprehension" begin
            @test jl2py("[x for x in 1:5]") == "[x for x in range(1, 6)]"
            @test jl2py("[x for x in 1:5 if x % 2 == 0]") ==
                  "[x for x in range(1, 6) if x % 2 == 0]"
            @test jl2py("[(x, y) for (x, y) in zip(1:5, 5:-1:1)]") ==
                  "[(x, y) for (x, y) in zip(range(1, 6), range(5, 0, -1))]"
            @test jl2py("[x + 2 for x in 1:5 if x > 0]") ==
                  "[x + 2 for x in range(1, 6) if x > 0]"
            @test jl2py("[x for x in 1:5 if x > 4 for y in 1:5 if y >4]") ==
                  "[x for x in range(1, 6) if x > 4 for y in range(1, 6) if y > 4]"
            @test jl2py("[1 for y in 1:5, z in 1:6 if y > z]") ==
                  "[1 for y in range(1, 6) for z in range(1, 7) if y > z]"

            @testset "GeneratorExp within Generator" begin
                @test jl2py("[x for x in 1:5 if x > 4 for y in 1:5 if y >4 for z in 1:sum(x for x in 1:5)]") ==
                      "[x for x in range(1, 6) if x > 4 for y in range(1, 6) if y > 4 for z in range(1, sum((x for x in range(1, 6))) + 1)]"
            end
        end

        @testset "Function call (and builtins)" begin
            @test jl2py("print(2)") == "print(2)"
            @test jl2py("println(2)") == "print(2)"
            @test jl2py("length(a)") == "len(a)"
            @test jl2py("sort([2, 3, 4])") == "sorted([2, 3, 4])"
            @test jl2py("sort!([1, 5, 3])") == "sort_inplace([1, 5, 3])" # The trailing "!" is replaced by "_inplace"
            @test jl2py("f(a)") == "f(a)"
            @test jl2py("f(a, b)") == "f(a, b)"
            @test jl2py("f(a, b; c = 2)") == "f(a, b, c=2)"
            @test jl2py("f(a, b; kw...)") == "f(a, b, **kw)"
            @test jl2py("f(a, b, d...; c = 2, e...)") == "f(a, b, *d, c=2, **e)"
            @test jl2py("f(g(x))") == "f(g(x))"
            @test jl2py("f(x)(y)") == "f(x)(y)"
            @test jl2py("Set{Int}([1,2,3])") == "set([1, 2, 3])"
        end

        @testset "Multi-line" begin
            @test jl2py("a = 2; b = 3") == "a = 2\nb = 3"
            @test jl2py("""
            begin
                function f(x::Int64, y::Int64)
                    x + y
                end
            
                a = f(3)
                f(4)
            end
        """) == "def f(x: int, y: int, /):\n    return x + y\na = f(3)\nf(4)"
        end

        @testset "Function defintion" begin
            @test jl2py("function f(x) end") == "def f(x, /):\n    pass"
            @test jl2py("function f(x) return x end") == "def f(x, /):\n    return x"
            @test jl2py("function f(x) y; x + 1 end") == "def f(x, /):\n    y\n    return x + 1"
            @test jl2py("function f(x) x + 2 end") == "def f(x, /):\n    return x + 2"
            @test jl2py("function f(x) x = 2 end") == "def f(x, /):\n    x = 2\n    return x"
            @test jl2py("function f(x) x += 2 end") == "def f(x, /):\n    x += 2\n    return x"
            @test jl2py("function f(x) g(x) end") == "def f(x, /):\n    return g(x)"
            @test jl2py("function f(x::Float64) x + 2 end") == "def f(x: float, /):\n    return x + 2"
            @test jl2py("function f(x::Int64, y) x + y end") == "def f(x: int, y, /):\n    return x + y"
            @test jl2py("function f(x::Int)::Int x end") == "def f(x: int, /) -> int:\n    return x"
            @test jl2py("function f(x=2, y=3) x + y end") == "def f(x=2, y=3, /):\n    return x + y"
            @test jl2py("function f(x::Int=2, y=3) x + y end") == "def f(x: int=2, y=3, /):\n    return x + y"
            @test jl2py("function f(;x::Int=2, y=3) x + y end") == "def f(*, x: int=2, y=3):\n    return x + y"
            @test jl2py("function f(b...;x::Float32=2, y) x + y end") ==
                  "def f(*b, x: float=2, y):\n    return x + y"
            @test jl2py("function f(a,b,c...;x::Float32=2, y) x + y end") ==
                  "def f(a, b, /, *c, x: float=2, y):\n    return x + y"
            @test jl2py("function f(a,b,c...;x::Float32=2, y, z...) x + y end") ==
                  "def f(a, b, /, *c, x: float=2, y, **z):\n    return x + y"
            @test jl2py("function f() for i in 1:10 print(i) end end") ==
                  "def f():\n    for i in range(1, 11):\n        print(i)"
        end

        @testset "Lambda" begin
            @test jl2py("x -> x + 1") == "lambda x, /: x + 1"
            @test jl2py("x::Float64 -> x + 1") == "lambda x: float, /: x + 1"
            @test jl2py("(x::Float64, y) -> x + y") == "lambda x: float, y, /: x + y"
            @test jl2py("(x::Float64, y)::Float64 -> x + y") == "lambda x: float, y, /: x + y"
        end

        @testset "Type annotations" begin
            @test jl2py("a::Nothing = nothing") == "(a): None = None"
            @test jl2py("a::Vector{Int} = 2") == "(a): List[int] = 2"
            @test jl2py("a::Set{Int} = Set([2, 3])") == "(a): Set[int] = set([2, 3])"
            @test jl2py("a::Dict{Int, Pair{Int, Tuple{String, Int, Char}}} = Dict()") ==
                  "(a): Dict[int, Tuple[int, Tuple[str, int, str]]] = {}"
            @test jl2py("a::Union{Int, Nothing} = nothing") ==
                  "(a): Union[int, None] = None"
            @test jl2py("a::ListNode = ListNode()") ==
                  "(a): ListNode = ListNode()" # Unknown types are not changed
        end
    end

    @testset "Misc" begin
        @testset "AST to AST" begin
            a = jl2py(1)
            @test pyconvert(Bool, pyisinstance(a, Jl2Py.AST.Constant) && a.value == 1)
        end

        @testset "Apply Polyfill" begin
            polyfill = read(joinpath(@__DIR__, "..", "polyfill", "polyfill.py"), String)

            @test jl2py("print(1)"; apply_polyfill=true) == polyfill * "\n" * "print(1)"
        end
    end
end
