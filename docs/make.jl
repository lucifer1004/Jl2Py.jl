using Jl2Py
using Documenter

DocMeta.setdocmeta!(Jl2Py, :DocTestSetup, :(using Jl2Py); recursive=true)

makedocs(;
    modules=[Jl2Py],
    authors="Gabriel Wu <wuzihua@pku.edu.cn> and contributors",
    repo="https://github.com/lucifer1004/Jl2Py.jl/blob/{commit}{path}#{line}",
    sitename="Jl2Py.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://lucifer1004.github.io/Jl2Py.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/lucifer1004/Jl2Py.jl",
    devbranch="main",
)
