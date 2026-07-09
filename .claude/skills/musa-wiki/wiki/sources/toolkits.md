---
title: "MUSA 工具套件 — 章节摘要"
type: source
status: active
created: 2026-07-10
updated: 2026-07-10
sources: [toolkits.md, toolkits_mcc_compiler.md, toolkits_mtrtc_runtime_compilation.md, toolkits_musa_runtime.md, toolkits_musify.md, toolkits_mupti.md, toolkits_moore_perf.md, toolkits_musa_mapping.md]
tags: [musa, toolkits, compiler, runtime, migration, profiling, compatibility]
---

# MUSA 工具套件 (MUSA Toolkits)

The MUSA Toolkits chapter covers the developer tools that make MUSA applications buildable, debuggable, portable, and performant.
It spans compilation, runtime, code migration, CUDA compatibility, runtime device compilation, profiling, and performance analysis.

## Chapter scope

This chapter is the SDK developer toolset layer:

- `toolkits.md` — chapter root and quick-start reference for the toolkit suite.
- `toolkits_mcc_compiler.md` — `mcc` compiler driver, host/device compilation, fatbin generation, phase control.
- `toolkits_mtrtc_runtime_compilation.md` — `MTRTC` runtime compilation library for compiling device source strings on the fly.
- `toolkits_musa_runtime.md` — MUSA Runtime library (`musart`), device management, memory, kernel launch, streams, events.
- `toolkits_musify.md` — `musify` CUDA→MUSA migration tool based on text matching.
- `toolkits_mupti.md` — `muPTI` profiling interface for activity tracing and host API callbacks.
- `toolkits_moore_perf.md` — Moore Perf toolset: `mcu`, `msys`, and GUI workflow.
- `toolkits_musa_mapping.md` — `MUSA Mapping` compile-time CUDA compatibility layer using a Clang plugin.

## Key takeaways

- The toolkit suite is the MUSA SDK's developer-facing layer: it makes source code compilation, runtime deployment, CUDA porting, and performance analysis practical.
- `mcc` is the central compiler driver. It manages host and device paths, embeds device fatbins, and supports multi-architecture targets.
- `musart` is the runtime library and the default link target for idiomatic MUSA applications.
- `MTRTC` is the runtime compilation path for dynamic kernel generation and lowered-name lookup.
- `musify` is a first-pass migration tool; it rewrites CUDA source text into MUSA source but is not aware of semantics.
- `MUSA Mapping` is the stronger compatibility path for compiling CUDA-style sources unchanged through `mcc` with a semantic Clang plugin.
- `muPTI` and Moore Perf are the primary profiling stack for measuring kernels, memory, and GPU utilization.

## Quick commands and workflows

### `mcc`

- Compile a simple MUSA program:

```bash
mcc main.mu -lmusart -o app
```

- Enable optimization and target MP31:

```bash
mcc -O3 -arch=mp31 main.mu -lmusart -o app
```

- Compile CUDA-style source with `cuda_wrapper` compatibility:

```bash
mcc -mtgpu -cuda_wrapper main.cu -lcuda2musa -lmusart -o app
```

- Override the SDK location:

```bash
mcc --musa-path=/opt/musa main.mu -lmusart -o app
```

### `MTRTC`

- Create a program from source text with `mtrtcCreateProgram`.
- Compile it with `mtrtcCompileProgram`.
- Read the build log with `mtrtcGetProgramLog`.
- Retrieve binary data with `mtrtcGetFatBin` and symbol names with `mtrtcGetLoweredName`.
- Load the result via Driver API (`muModuleLoadData`, `muModuleGetFunction`).

### `musify`

- Convert a single file:

```bash
musify-text --inplace source.cu
```

- Convert a whole directory:

```bash
musify-text -r src/ -o musa_src/
```

- Use custom mappings when the defaults are insufficient.

### `MUSA Mapping`

- Use `MUSA Mapping` when you need to keep CUDA source unchanged on disk.
- Compile with the `mcc_wrapper` or load `libMusaMapping.so` as a plugin.
- It is best for large third-party codebases where source rewrite is too risky.

## When to use each toolkit

- Use `mcc` for normal MUSA development and production builds.
- Use `musart` when building and running applications with MUSA's high-level Runtime API.
- Use `MTRTC` when kernel source is generated or selected at runtime and you need JIT compilation.
- Use `musify` when porting CUDA code and you want a mechanical first pass.
- Use `MUSA Mapping` when you need to compile CUDA-style source directly without editing the original files.
- Use `muPTI` for programmatic instrumentation or custom profiling integrations.
- Use `Moore Perf` (`mcu`, `msys`, GUI) for end-to-end performance analysis and timeline debugging.

## Cross-References

- [[mcc-compiler]] — MUSA compiler driver
- [[musart-runtime]] — MUSA Runtime library
- [[mtrtc]] — runtime compilation library
- [[musify-tool]] — CUDA→MUSA migration tool
- [[musa-mapping]] — compile-time CUDA compatibility layer
- [[mupti]] — profiling Tools Interface
- [[moore-perf]] — Moore Perf profiler toolset
- [[cuda-to-musa-mapping]] — porting correspondence between CUDA and MUSA
- [[musa-sdk-stack]] — where the toolkits fit in the SDK stack
- [[sources/what_is_musa]] — SDK overview and toolchain context
