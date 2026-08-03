# ManyUICImGui.jl

Dear ImGui backend for the [ManyUI](https://github.com/s-celles/ManyUI.jl)
ecosystem. This repository is the initial scaffold; the backend implementation
will be added incrementally without changing the core ManyUI widget API.

See [ROADMAP.md](ROADMAP.md) for the cross-backend parity plan.

The package remains headless-testable by default. To enable the native GLFW /
OpenGL3 Dear ImGui window seam, install the optional graphics dependencies:

```julia
import Pkg
Pkg.add(["CImGui", "GLFW", "ModernGL"])
```

Then call `ManyUICImGui.launch_manyui(() -> ui())` for the first supported
projection (`Container`, `Label`, `Static` and `Button`), or use
`launch_imgui(ui)` with a function containing direct CImGui drawing calls.
Additional ManyUI widgets are being mapped incrementally.

[![Build Status](https://github.com/s-celles/ManyUICImGui.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/s-celles/ManyUICImGui.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
