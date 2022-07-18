# Jl2Py

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://lucifer1004.github.io/Jl2Py.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://lucifer1004.github.io/Jl2Py.jl/dev)
[![Build Status](https://github.com/lucifer1004/Jl2Py.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/lucifer1004/Jl2Py.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/lucifer1004/Jl2Py.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/lucifer1004/Jl2Py.jl)

## Examples

Conversion results of [LeetCode.jl - 1. Two Sum](https://github.com/JuliaCN/LeetCode.jl/blob/master/src/problems/1.two-sum.jl)

```python
def two_sum(nums: List[int], target: int, /) -> Union[None, Tuple[int, int]]:
    seen = {}
    x = 2
    for (i, n) in enumerate(nums):
        m = target - n
        if haskey(seen, m):
            return (seen[m], i)
        else:
            seen[n] = i
```

Conversion results of [LeetCode.jl - 2. Add Two Numbers](https://github.com/JuliaCN/LeetCode.jl/blob/master/src/problems/2.add-two-numbers.jl)

```python
def add_two_numbers(l1: ListNode, l2: ListNode, /) -> ListNode:
    carry = 0
    fake_head = cur = ListNode()
    while not isnothing(l1) or (not isnothing(l2) or not iszero(carry)):
        (v1, v2) = (0, 0)
        if not isnothing(l1):
            v1 = val(l1)
            l1 = next(l1)
        if not isnothing(l2):
            v2 = val(l2)
            l2 = next(l2)
        (carry, v) = divrem(v1 + v2 + carry, 10)
        next_inplace(cur, ListNode(v))
        cur = next(cur)
        val_inplace(cur, v)
    return next(fake_head)
```

We can see that we only need to define a few polyfill functions to make the generated Python code work.
