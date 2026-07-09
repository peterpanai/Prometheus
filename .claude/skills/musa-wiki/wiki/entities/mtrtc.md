---
title: "MTRTC"
type: entity
status: active
created: 2026-07-10
updated: 2026-07-10
sources: [toolkits_mtrtc_runtime_compilation.md]
tags: [musa, runtime, compilation, jit, codegen]
---

# MTRTC

`MTRTC` is the MUSA runtime compilation library. It compiles device code from strings at runtime, produces binary/fatbin output, and exposes lowered symbol names for dynamic module loading.

## What it is

- A runtime library shipped as `libmtrtc.so`.
- Designed for scenarios where device source is generated or selected at runtime.
- Works with `MUSA Driver API` to load the compiled binary and launch kernels.

## Typical workflow

1. Call `mtrtcCreateProgram` with device source text and optional in-memory headers.
2. Optionally register name expressions with `mtrtcAddNameExpression` for template or C++ mangled symbols.
3. Compile with `mtrtcCompileProgram` and collect build logs.
4. Retrieve the binary image with `mtrtcGetFatBin` and symbol mappings with `mtrtcGetLoweredName`.
5. Load the resulting module through Driver API (`muModuleLoadData`, `muModuleGetFunction`, etc.).

## Why use it

- Ideal when the kernel source is not known until runtime.
- Avoids the need to precompile every variant.
- Supports repeated compilations of the same `mtrtcProgram` with different options.
- Provides a way to map high-level names to lowered runtime symbols.

## Important notes

- `mtrtcAddNameExpression` must be called before compilation if you need consistent symbol lookup.
- `mtrtcGetLoweredName` results are only valid while the program object remains live.
- Recompiling the same `mtrtcProgram` invalidates previous logs, fatbins, and lowered-name results.
- Use `MTRTC` when dynamic source generation or runtime code specialization is a core requirement.

## Cross-References

- [[musart-runtime]] — runtime library and high-level API
- [[musadrv-driver]] — Driver API module loading and kernel launch
- [[mcc-compiler]] — offline compilation counterpart
- [[musa-sdk-stack]] — developer toolchain layer
- [[sources/toolkits]] — toolkit chapter summary
- [[cuda-to-musa-mapping]] — porting and compatibility context
