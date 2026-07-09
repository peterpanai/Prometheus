---
title: "muPTI"
type: entity
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [performance_tuning_perf_tools.md, what_is_musa_musa_sdk.md, toolkits_mupti.md]
tags: [musa, mupti, profiling, tracing, callbacks, instrumentation]
---

# muPTI

muPTI (MUSA Profiling Tools Interface) is the low-level profiling API — programmatic access to GPU events, kernel timing, and hardware counters. It is the foundation that `mcu` and `msys` are built on. Use it when you need profiling embedded in your application (e.g. an auto-tuner, a framework's profiler, or a custom monitoring tool).

## What It Provides

| Capability | API |
|------------|-----|
| **Activity tracing** | `muptiActivityEnable`, `muptiActivityRegisterCallbacks`, `muptiActivityConsumeCurrentRecord` |
| **Callback on host API events** | `muptiSubscribe`, `muptiEnableDomain` |
| **Counter collection** | `muptiCounterGetNumEnumerators`, `muptiCounterCreate`, `muptiCounterRead` |
| **Metric collection** | `muptiMetricGetNumEnumerators`, `muptiMetricCreate`, `muptiMetricReadValue` |
| **Kernel properties** | `muptiKernelGetAttribute`, `muptiKernelSetAttribute` |

## Activity Tracing — The Most Common Use

```cpp
#include <mupti.h>

void MUPTIAPI activityCallback(const char* activity_type, ...) {
    // Called by muPTI when an activity record is ready
    // (e.g., kernel completed, memcpy completed)
}

muptiSubscribe(&subscriber, activityCallback, nullptr);
muptiActivityEnable(MUPTI_ACTIVITY_KIND_KERNEL);
muptiActivityEnable(MUPTI_ACTIVITY_KIND_MEMCPY);
// ... run your workload ...
muptiActivityFlushAll(0);
```

Records contain:
- Kernel name, stream, grid/block dim, shared mem size
- Start/end timestamps
- Correlation ID (to match host API call with device activity)

## Host API Callbacks

```cpp
void MUPTIAPI callbackHandler(muptiDomain domain, muptiCallbackId id, const void* data) {
    if (id == MUPTI_RUNTIME_TRACE_CBID_KERNEL_LAUNCH) {
        const muptiCallbackData* cb = (const muptiCallbackData*)data;
        printf("Launching kernel: %s\n", cb->symbolName);
    }
}

muptiSubscribe(&subscriber, callbackHandler, nullptr);
muptiEnableDomain(1, subscriber, MUPTI_DOMAIN_RUNTIME_API);
// ... run workload ...
muptiUnsubscribe(subscriber);
```

> **Warning**: Callbacks run on the host thread that issued the API call. Don't do heavy work in the callback — it will block your application.

## Collecting Hardware Counters

```cpp
// Discover available counters
uint32_t numCounters;
muptiCounterGetNumEnumerators(device, &numCounters);

muptiCounter_t counter;
muptiCounterCreate(device, "sm_inst_executed.sum", &counter);

// Start collecting
muptiCounterGroupStart(device);

// Run your kernel
kernel<<<grid, block>>>(args);
musaDeviceSynchronize();

// Stop and read
uint64_t value;
muptiCounterGroupStop(device);
muptiCounterRead(device, counter, &value);

muptiCounterDestroy(device, counter);
```

## Metrics

A metric is a derived value from one or more counters (e.g., "DRAM utilization" = bytes_read + bytes_written / time):

```cpp
muptiMetric_t metric;
muptiMetricCreate(device, "dram_utilization", &metric);
// ... measure ...
double value;
muptiMetricReadValue(device, metric, &value);
```

muPTI ships with a library of pre-defined metrics — see the SDK docs for the full list.

## Correlation IDs

Each host API call gets a correlation ID. When the corresponding device activity happens, the same ID appears in the activity record. Use this to match "I launched this kernel" with "this kernel ran for X ms":

```cpp
// In the host API callback:
uint32_t hostCorrId;
muptiGetCorrelationId(&hostCorrId);
printf("Host launched kernel, corrId=%u\n", hostCorrId);

// In the activity callback:
muptiActivityKernel* k = (muptiActivityKernel*)record;
printf("Device ran kernel corrId=%u, took %llu ns\n", k->correlationId, k->end - k->start);
```

## Use Cases

| Use case | Approach |
|----------|----------|
| **Auto-tuner**: try N tile sizes, pick best | Use activity tracing, measure each kernel's duration |
| **Framework profiler** (e.g. PyTorch profiler) | Subscribe to runtime API + activity, generate Chrome trace JSON |
| **Continuous monitoring** | Periodic counter reads, ship to metrics system |
| **Anomaly detection** | Compare current kernel duration to historical baseline |
| **Replay/debug** | Record all activity, replay offline |

## Chrome Trace Export

A common pattern: convert muPTI activity records to Chrome's trace format (`chrome://tracing`):

```json
{"traceEvents":[
  {"name":"kernelA","cat":"kernel","ph":"X","ts":1234,"dur":5678,"pid":0,"tid":0},
  {"name":"memcpyH2D","cat":"memcpy","ph":"X","ts":1234,"dur":100,"pid":0,"tid":1}
]}
```

Open in a browser — get a free timeline visualizer.

## Performance Overhead

| Capability | Overhead |
|------------|----------|
| Host API callbacks | ~1-10 μs per call |
| Activity tracing (kernel/memcpy) | <1% typical |
| Hardware counters | 5-20% (varies by counter) |
| Metrics | Higher (multiple counter reads) |

For production profiling, prefer activity tracing over counters — lower overhead.

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Forgetting `muptiActivityFlushAll` at end | Lose last batch of records |
| Heavy work in callback | Blocks the application — queue and process async |
| Counter group not started | `muptiCounterRead` returns zero |
| Subscriber not unsubscribed | Memory leak |
| Multiple subscribers on same domain | Undefined behavior — use one subscriber |

## Cross-References

- [[moore-perf]] — built on muPTI
- [[roofline-model]] — counter data feeds the roofline
- [[occupancy]] — counter for achieved occupancy
- [[musa-sdk-stack]] — tooling layer
- → raw: `performance_tuning_perf_tools.md`
