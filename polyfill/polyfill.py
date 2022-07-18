from typing import *


def haskey(container, key) -> bool:
    return key in container


def isnothing(x) -> bool:
    return x is None


def iszero(x) -> bool:
    return x == 0


def divrem(x, y) -> Tuple:
    return x // y, x % y


def sort_inplace(x: list, rev: bool = False):
    x.sort(reverse=rev)
    return x


def push_inplace(x: Union[list, set, dict], *y):
    if isinstance(x, list):
        for yi in y:
            x.append(yi)
    elif isinstance(x, set):
        for yi in y:
            x.add(yi)
    elif isinstance(x, dict):
        for yi in y:
            assert(isinstance(yi, tuple) and len(yi) == 2)
            x[yi[0]] = yi[1]
    return x


def delete_inplace(x, k):
    if isinstance(x, set) and k in x:
        x.remove(k)
    elif isinstance(x, dict) and k in x:
        del x[k]
    return x


def union_inplace(x: set, y: set):
    x = x | y
    return x
