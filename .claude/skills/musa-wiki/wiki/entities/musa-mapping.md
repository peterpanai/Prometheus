---
title: "MUSA Mapping"
type: entity
status: active
created: 2026-07-10
updated: 2026-07-10
sources: [toolkits_musa_mapping.md]
tags: [musa, cuda-porting, compatibility, clang-plugin, compilation]
---

# MUSA Mapping

`MUSA Mapping` is a compile-time CUDA compatibility layer in the MUSA SDK. It uses a Clang plugin to rewrite CUDA-style source and headers during `mcc` compilation, while leaving the original `.cu` files unchanged on disk.

## What it does

- Loads `libMusaMapping.so` during `mcc` compilation.
- Rewrites `#include` directives, identifiers, macros, and CUDA-specific symbols to MUSA equivalents.
- Uses JSON-based mapping tables and `custom_defines.h` for semantic conversion.
- Supports large third-party codebases where source modification is undesirable.

## How it differs from musify

| Feature | musify | MUSA Mapping |
|---------|--------|--------------|
| Timing | offline source rewrite | compile-time plugin rewrite |
| Method | text matching | Clang AST-aware transformation |
| Disk changes | writes converted `.mu` files | no source file modifications |
| Best for | initial migration | large codebases, build compatibility |

## Typical usage

- Set `MUSA_HOME` to the SDK installation.
- Use the provided `mcc_wrapper` or `-fplugin` invocation.
- Compile CUDA-style sources with `mcc` as if they were MUSA sources.

## When to use it

- When you need to build unmodified CUDA source with MUSA tools.
- When you want a stronger semantic compatibility path than `musify`.
- When working with a large, third-party CUDA codebase where source rewrite is too risky.

## Important notes

- `MUSA Mapping` is installed under `$MUSA_HOME/tools/musamapping/`.
- Its default mapping tables cover CUDA SDK headers and common ecosystem headers.
- It is not a runtime translator; it operates during `mcc` compilation.
- For the strongest compatibility story, use it together with `mcc` and `musart`.

## Cross-References

- [[mcc-compiler]] — MUSA compiler driver that loads the plugin
- [[musify-tool]] — offline migration alternative
- [[musa-sdk-stack]] — SDK toolchain layer
- [[sources/toolkits]] — toolkit chapter summary
- [[cuda-to-musa-mapping]] — source-level portability mapping
