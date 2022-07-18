from typing import *


def haskey(container, key) -> bool:
    return key in container


def isnothing(x) -> bool:
    return x is None


def iszero(x) -> bool:
    return x == 0


def divrem(x, y) -> Tuple:
    return x // y, x % y
