using Jl2Py
using Test

@testset "Jl2Py.jl" begin
    # Literal constants
    @test jl2py("2") == "2"
    @test jl2py("2.0") == "2.0"
    @test jl2py("\"hello\"") == "'hello'"
    @test jl2py("false") == "False"
    @test jl2py("true") == "True"
    @test jl2py("foo") == "foo"

    # UAdd & USub
    @test jl2py("+3") == "3"
    @test jl2py("-3") == "-3"
    @test jl2py("+a") == "+a"
    @test jl2py("-a") == "-a"

    # Add
    @test jl2py("1 + 1") == "1 + 1"
    @test jl2py("1 + 1 + 1") == "1 + 1 + 1"
    @test jl2py("1 + 1 + 1 + 1") == "1 + 1 + 1 + 1"
    @test jl2py("a + 2") == "a + 2"
    @test jl2py("a + b") == "a + b"

    # Sub
    @test jl2py("1 - 1") == "1 - 1"
    @test jl2py("a - 2") == "a - 2"
    @test jl2py("a - b") == "a - b"

    # Mult
    @test jl2py("1 * 2") == "1 * 2"
    @test jl2py("1 * 2 * 3") == "1 * 2 * 3"

    # Div & FloorDiv
    @test jl2py("1 / 2") == "1 / 2"
    @test jl2py("1 ÷ 3") == "1 // 3"
    @test jl2py("div(3, 1)") == "3 // 1"

    # Mod
    @test jl2py("1 % 2") == "1 % 2"
    @test jl2py("mod(3, 1)") == "3 % 1"

    # Pow
    @test jl2py("10 ^ 5") == "10 ** 5"

    # Bitwise operators
    @test jl2py("~2") == "~2"
    @test jl2py("1 & 2") == "1 & 2"
    @test jl2py("1 | 2") == "1 | 2"
    @test jl2py("1 ⊻ 2") == "1 ^ 2"
    @test jl2py("xor(1, 2)") == "1 ^ 2"
    @test jl2py("1 << 2") == "1 << 2"
    @test jl2py("1 >> 2") == "1 >> 2"
    @test jl2py("1 + (-2 * 6) >> 2") == "1 + (-2 * 6 >> 2)" # Note the different association order

    # Logical operators
    @test jl2py("!true") == "not True"
    @test jl2py("!false") == "not False"
    @test jl2py("!a") == "not a"
    @test jl2py("true && false") == "True and False"
    @test jl2py("true || false") == "True or False"

    # Complex arithmetic
    @test jl2py("(1 + 5) * (2 - 5) / (3 * 6)") == "(1 + 5) * (2 - 5) / (3 * 6)"

    # Binary comparisons
    @test jl2py("1 == 2") == "1 == 2"
    @test jl2py("1 === 2") == "1 == 2"
    @test jl2py("1 != 2") == "1 != 2"
    @test jl2py("1 < 2") == "1 < 2"
    @test jl2py("1 <= 2") == "1 <= 2"
    @test jl2py("1 > 2") == "1 > 2"
    @test jl2py("1 >= 2") == "1 >= 2"

    # Multiple comparisons
    @test jl2py("1 < 2 < 3") == "1 < 2 < 3"
    @test jl2py("1 < 2 < 3 < 4") == "1 < 2 < 3 < 4"
    @test jl2py("3 > 2 != 3 == 3") == "3 > 2 != 3 == 3"

    # List
    @test jl2py("[1, 2, 3]") == "[1, 2, 3]"
    @test jl2py("[1, 2 + 3, 3]") == "[1, 2 + 3, 3]"
    @test jl2py("[1, 2, [3, 4], []]") == "[1, 2, [3, 4], []]"

    # Assign
    @test jl2py("a = 2") == "a = 2"
    @test jl2py("a = 2 + 3") == "a = 2 + 3"
    @test jl2py("a = b = 2") == "a = b = 2"
    @test jl2py("a = b = c = 23 + 3") == "a = b = c = 23 + 3"

    # Function call
    @test jl2py("print(2)") == "print(2)"
end
