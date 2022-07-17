using Jl2Py
using Test

@testset "Jl2Py.jl" begin
    @testset "Literal constants" begin
        @test jl2py("2") == "2"
        @test jl2py("2.0") == "2.0"
        @test jl2py("\"hello\"") == "'hello'"
        @test jl2py("false") == "False"
        @test jl2py("true") == "True"
        @test jl2py("foo") == "foo"
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
    end

    @testset "Multiple comparisons" begin
        @test jl2py("1 < 2 < 3") == "1 < 2 < 3"
        @test jl2py("1 < 2 < 3 < 4") == "1 < 2 < 3 < 4"
        @test jl2py("3 > 2 != 3 == 3") == "3 > 2 != 3 == 3"
    end

    @testset "Ranges" begin
        @test jl2py("1:10") == "range(1, 10)"
        @test jl2py("1:2:10") == "range(1, 10, 2)"
    end

    @testset "List" begin
        @test jl2py("[1, 2, 3]") == "[1, 2, 3]"
        @test jl2py("[1, 2 + 3, 3]") == "[1, 2 + 3, 3]"
        @test jl2py("[1, 2, [3, 4], []]") == "[1, 2, [3, 4], []]"
    end

    @testset "Set" begin
        @test jl2py("Set(1, 2, 3)") == "{1, 2, 3}"
        @test jl2py("Set{Number}(1, 2, 3)") == "{1, 2, 3}"
    end

    @testset "Dict" begin
        @test jl2py("Dict(1=>2, 3=>14)") == "{1: 2, 3: 14}"
        @test jl2py("Dict{Number,Number}(1=>2, 3=>14)") == "{1: 2, 3: 14}" # Type info is discarded
    end

    @testset "Assign" begin
        @test jl2py("a = 2") == "a = 2"
        @test jl2py("a = 2 + 3") == "a = 2 + 3"
        @test jl2py("a = b = 2") == "a = b = 2"
        @test jl2py("a = b = c = 23 + 3") == "a = b = c = 23 + 3"
    end

    @testset "Function call" begin
        @test jl2py("print(2)") == "print(2)"
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
    """) == "def f(x: int, y: int):\n    return x + y\na = f(3)\nf(4)"
    end

    @testset "Function defintion" begin
        @test jl2py("function f(x) end") == "def f(x):\n    pass"
        @test jl2py("function f(x) x + 2 end") == "def f(x):\n    return x + 2"
        @test jl2py("function f(x::Float64) x + 2 end") == "def f(x: float):\n    return x + 2"
        @test jl2py("function f(x::Int64, y) x + y end") == "def f(x: int, y):\n    return x + y"
    end
end
