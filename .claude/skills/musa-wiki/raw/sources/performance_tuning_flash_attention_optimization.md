<!--
Source: https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/programming_guide/performance/tuning_flash_attention_optimization
Title: FlashAttention 优化
Fetched: 2026-07-07
This file is an immutable raw source. Do not edit.
-->

# FlashAttention 优化

FlashAttention 优化核心原则

1.  避免存储完整的注意力矩阵（O(N²) 显存）
2.  online softmax（在线 Softmax）消除全局依赖
3.  分块（Tiling）计算，充分利用片上 SRAM
4.  重计算（Recompute）换存储

FlashAttention 是一种 IO-aware attention 算法。它不改变 self-attention 的数学结果，而是通过分块、online softmax 和重计算减少对 HBM 的读写。

| 读者目标                      | 建议先看                                            |
|-------------------------------|-----------------------------------------------------|
| 理解为什么需要 FlashAttention | 标准 Self-Attention 的问题、FlashAttention 核心创新 |
| 理解算法如何工作              | online softmax、FlashAttention 完整算法             |
| 做 kernel 参数调优            | 块大小选择、软件流水线、寄存器压力管理              |

------------------------------------------------------------------------

## 标准 Self-Attention 的问题

标准 self-attention 会显式生成 $N \times N$<span aria-hidden="true">N×N</span> 的注意力矩阵。序列越长，注意力矩阵带来的显存和访存压力越明显，这也是 FlashAttention 主要要解决的问题。

- 计算流程
- 显存压力

<div role="tabpanel">

### 标准 Attention 公式

$$\text{Attention}(Q,K,V) = \text{softmax}\left( \frac{QK^{T}}{\sqrt{d}} \right)V$$<span aria-hidden="true">Attention(Q,K,V)=softmax(d​QKT​)V</span>

其中：

- $Q,K,V$<span aria-hidden="true">Q,K,V</span> 是 $N \times d$<span aria-hidden="true">N×d</span> 矩阵（N 为序列长度，d 为隐藏维度）
- 输出 $O$<span aria-hidden="true">O</span> 也是 $N \times d$<span aria-hidden="true">N×d</span> 矩阵

### 标准实现的三步计算

```text
Step 1: S = Q × K^T          (N × N 注意力矩阵)
Step 2: P = softmax(S)       (N × N 概率矩阵)
Step 3: O = P × V            (N × d 输出矩阵)
```

<div role="tabpanel" hidden="">

### 显存需求分析

| 矩阵               | Shape     | 显存占用（FP16）    |
|--------------------|-----------|---------------------|
| Q, K, V            | N × d     | 3 × 2N × d Bytes    |
| **S (注意力矩阵)** | **N × N** | **2N² Bytes**       |
| **P (概率矩阵)**   | **N × N** | **2N² Bytes**       |
| O                  | N × d     | 2N × d Bytes        |
| **总计**           | \-        | **4N² + 8Nd Bytes** |

**问题**：当 N 较大时，N² 项主导显存占用

**示例**：N=4096, d=128

- Q, K, V: 3 × 2 × 4096 × 128 = 3MB
- **S, P: 4 × 4096² = 128MB**（占 97%！）

### 长序列的显存瓶颈

| 序列长度 | S+P 显存占用 | 是否可接受           |
|----------|--------------|----------------------|
| N=512    | 2MB          | 可接受               |
| N=2048   | 32MB         | 需关注               |
| N=4096   | 128MB        | 显存压力明显增加     |
| N=16384  | 2GB          | 长序列场景需重点评估 |

------------------------------------------------------------------------

## FlashAttention 核心创新

### FlashAttention 概述

FlashAttention 的核心不是近似计算，而是改变 attention kernel 的数据流。它把 Q/K/V 分块加载到片上 SRAM，在块内完成矩阵乘、softmax 更新和输出累加，避免将完整的 $S$<span aria-hidden="true">S</span> 和 $P$<span aria-hidden="true">P</span> 矩阵写回全局内存。

| 创新点                  | 作用                    | 效果                  |
|-------------------------|-------------------------|-----------------------|
| **分块**（Tiling）      | 将大矩阵分解为小块      | 控制片上 SRAM 占用    |
| **Recompute（重计算）** | 避免存储完整注意力矩阵  | 显存降低 O(N²) → O(N) |
| **IO 感知设计**         | 优化 GPU 内存层次数据流 | 带宽利用率提升        |

### 关键挑战：Softmax 的全局依赖

**Softmax 公式**：

$$P_{i} = \frac{e^{S_{i}}}{\sum\limits_{j}e^{S_{j}}}$$<span aria-hidden="true">Pi​=∑j​eSj​eSi​​</span>

**问题**：分母需要全局求和，无法直接分块计算

**解决方案**：online softmax（在线 Softmax）

------------------------------------------------------------------------

## online softmax（在线 Softmax）

### 标准 Softmax 回顾

```python
# 标准 Softmax（需要三次循环）
# 计算最大值（用于数值稳定）
m = max(S)

# 计算分母（需要第一次循环结束后才能开始）
Z = sum(exp(S - m))

# 计算输出（需要第二次循环结束后才能开始）
P = exp(S - m) / Z
```

**问题**：三次循环，无法融合，访存效率低

### online softmax（在线 Softmax）核心思想

**关键洞察**：推导 $\ell_{j}$<span aria-hidden="true">ℓj​</span> 和 $m_{j}$<span aria-hidden="true">mj​</span> 的递归公式，消除全局依赖

**定义**：

- $m_{j} = {\max}_{0 \leq i \leq j}S_{i}$<span aria-hidden="true">mj​=max0≤i≤j​Si​</span>（前 j 项最大值）
- $\ell_{j} = \sum_{i = 0}^{j}e^{S_{i} - m_{j}}$<span aria-hidden="true">ℓj​=∑i=0j​eSi​−mj​</span>（归一化分母）

**递归关系**：

$$m_{j} = \max(m_{j - 1},S_{j})$$<span aria-hidden="true">mj​=max(mj−1​,Sj​)</span> $$\ell_{j} = e^{m_{j - 1} - m_{j}} \cdot \ell_{j - 1} + e^{S_{j} - m_{j}}$$<span aria-hidden="true">ℓj​=emj−1​−mj​⋅ℓj−1​+eSj​−mj​</span>

### online softmax（在线 Softmax）算法

```python
# online softmax（单次循环）
m = -inf      #  运行最大值（running maximum）
ell = 0.0     #  运行分母（running denominator）

for j in range(N):
    # 更新最大值和分母
    m_new = max(m, S[j])
    ell_new = exp(m - m_new) * ell + exp(S[j] - m_new)
    
    # 更新输出（递归调整之前的值）
    for i in range(j + 1):
        P[i] = P[i] * exp(m - m_new)
    P[j] = exp(S[j] - m_new) / ell_new
    
    # 更新状态
    m = m_new
    ell = ell_new
```

**优势**：

- 单次循环即可完成
- 中间状态 $m,\ell$<span aria-hidden="true">m,ℓ</span> 可保存在 SRAM 中
- 无需存储完整的 S 矩阵

### online softmax（在线 Softmax）数值稳定性

**Safe Softmax 技巧**：

$$P_{i} = \frac{e^{S_{i} - m}}{\sum\limits_{j}e^{S_{j} - m}}$$<span aria-hidden="true">Pi​=∑j​eSj​−meSi​−m​</span>

其中 $m = \max(S)$<span aria-hidden="true">m=max(S)</span>，避免数值溢出。

**online softmax 天然支持**：

- 递归公式中已包含减最大值操作
- 无需额外处理

------------------------------------------------------------------------

## FlashAttention 完整算法

FlashAttention 的执行路径可以先按“加载 Q 块、遍历 K/V 块、在线更新 softmax 状态、写回输出”来理解。公式适合核对数学等价性，流程图适合理解 kernel 数据流，伪代码只用于说明结构。

- 公式
- 流程
- 伪代码结构

<div role="tabpanel">

### FlashAttention 公式推导

**结合 online softmax 后的 Attention**：

$$\begin{matrix}
 & {\text{对于每个输出块~}O_{i}:} \\
 & {1.\text{~加载~}Q_{i}\text{~(B}_{c} \times d\text{)}} \\
 & {2.\text{~初始化~}m_{i} = - \infty,\ell_{i} = 0,O_{i} = 0} \\
 & {3.\text{~对于每个~K,~V~块~}j:} \\
 & {\quad\text{a.~加载~}K_{j},V_{j}} \\
 & {\quad\text{b.~计算~}S_{ij} = Q_{i}K_{j}^{T}} \\
 & {\quad\text{c.~计算~}m_{ij} = \max(m_{i},\text{rowmax}(S_{ij}))} \\
 & {\quad\text{d.~更新~}\ell_{i} = e^{m_{i} - m_{ij}}\ell_{i} + \text{rowsum}(e^{S_{ij} - m_{ij}})} \\
 & {\quad\text{e.~更新~}O_{i} = \text{diag}(e^{m_{i} - m_{ij}})O_{i} + e^{S_{ij} - m_{ij}}V_{j}} \\
 & {\quad\text{f.~更新~}m_{i} = m_{ij}} \\
 & {4.\text{~归一化~}O_{i} = O_{i}/\ell_{i}}
\end{matrix}$$<span aria-hidden="true">​对于每个输出块 Oi​:1. 加载 Qi​ (Bc​×d)2. 初始化 mi​=−∞,ℓi​=0,Oi​=03. 对于每个 K, V 块 j:a. 加载 Kj​,Vj​b. 计算 Sij​=Qi​KjT​c. 计算 mij​=max(mi​,rowmax(Sij​))d. 更新 ℓi​=emi​−mij​ℓi​+rowsum(eSij​−mij​)e. 更新 Oi​=diag(emi​−mij​)Oi​+eSij​−mij​Vj​f. 更新 mi​=mij​4. 归一化 Oi​=Oi​/ℓi​​</span>

<div role="tabpanel" hidden="">

### FlashAttention 算法流程

```text
┌───────────────────────────────────────────────────────────────┐
│                FlashAttention 单块计算流程                     │
├───────────────────────────────────────────────────────────────┤
│                                                                │
│  输入：Q 块 (Bc×d), K 块序列 {Kj}, V 块序列 {Vj}                │
│  输出：O 块 (Bc×d)                                             │
│                                                                │
│  1. 加载 Q 块到 SRAM                                           │
│  2. 初始化 m = -∞, ℓ = 0, O = 0                               │
│                                                                │
│  3. For each K/V 块 j:                                         │
│     ┌────────────────────────────────────────────┐            │
│     │ a. 加载 Kj, Vj 到 SRAM                     │            │
│     │ b. 计算 Sij = Qi × Kj^T  (Bc×Bc 矩阵)      │            │
│     │ c. 计算 mij = max(m, rowmax(Sij))          │            │
│     │ d. 更新 ℓ = exp(m-mij)×ℓ + rowsum(exp(Sij-mij))  │      │
│     │ e. 更新 O = diag(exp(m-mij))×O + exp(Sij-mij)×Vj  │     │
│     │ f. 更新 m = mij                            │            │
│     └────────────────────────────────────────────┘            │
│                                                                │
│  4. 归一化 O = O / ℓ                                           │
│  5. 写回 O 块到全局内存                                         │
│                                                                │
└───────────────────────────────────────────────────────────────┘
```

<div role="tabpanel" hidden="">

### FlashAttention 代码结构

信息

以下代码是用于说明数据流的伪代码骨架，省略了线程映射、向量化加载、边界处理、矩阵指令调用和逐行 softmax 状态等实现细节，不能作为独立 kernel 直接编译。

```cpp
template<int Bc, int Br, int d>
__global__ void flashAttention(
    float* Q, float* K, float* V, float* O,
    int N, int d_model
) {
    // 共享内存
    __shared__ float Q_shared[Bc][d];
    __shared__ float K_shared[Br][d];
    __shared__ float V_shared[Br][d];
    
    // 寄存器状态
    float m_i = -INFINITY;  // running max
    float ell_i = 0.0f;     // 运行分母（running denominator）
    float O_accum[Bc][d] = {0.0f};  // 累加器
    
    // Block 索引
    int bx = blockIdx.x;
    int by = blockIdx.y;
    
    // 加载 Q 块到 SRAM
    loadQBlock(Q, bx, by, Q_shared);
    __syncthreads();
    
    // 主循环：遍历所有 K/V 块
    for (int j = 0; j < (N + Br - 1) / Br; j++) {
        // 加载 K, V 块
        loadKVBlock(K, V, j, K_shared, V_shared);
        __syncthreads();
        
        // 计算 Sij = Qi × Kj^T
        float S[Bc][Br];
        computeS(Q_shared, K_shared, S);
        
        // online softmax 更新
        float m_new = -INFINITY;
        float P[Bc][Br];
        
        // 计算新的最大值
        for (int i = 0; i < Bc; i++) {
            for (int jj = 0; jj < Br; jj++) {
                m_new = max(m_new, S[i][jj]);
            }
        }
        m_new = max(m_i, m_new);
        
        // 计算概率并更新累加器
        float scale = exp(m_i - m_new);
        ell_i = ell_i * scale;
        
        for (int i = 0; i < Bc; i++) {
            for (int jj = 0; jj < Br; jj++) {
                P[i][jj] = exp(S[i][jj] - m_new);
                ell_i += P[i][jj];
            }
        }
        
        // 更新 O = diag(scale) × O + P × V
        updateO(O_accum, P, V_shared, scale);
        
        // 更新状态
        m_i = m_new;
        __syncthreads();
    }
    
    // 归一化
    for (int i = 0; i < Bc; i++) {
        for (int j = 0; j < d; j++) {
            O_accum[i][j] /= ell_i;
        }
    }
    
    // 写回结果
    storeOBlock(O, bx, by, O_accum);
}
```

------------------------------------------------------------------------

## FlashAttention 实现细节

实现时通常先确定块大小，再设计数据搬运流水线，最后用编译器报告和性能分析工具检查寄存器压力。下面三个标签页对应这三个调优入口。

- 块大小
- 软件流水线
- 寄存器压力

<div role="tabpanel">

### 块大小（Block Size）选择

**关键约束**：共享内存容量限制

对于 MP31 架构（单 MP 192KB 共享内存）：

$$\text{SRAM~需求} \approx (B_{c} \times d + 2 \times B_{r} \times d) \times \text{sizeof(dtype)} + \text{额外状态缓冲}$$<span aria-hidden="true">SRAM 需求≈(Bc​×d+2×Br​×d)×sizeof(dtype)+额外状态缓冲</span>

**典型配置**（d=128, FP16）：

| 参数                                      | 值     | 说明       |
|-------------------------------------------|--------|------------|
| $B_{c}$<span aria-hidden="true">Bc​</span> | 256    | Q 块大小   |
| $B_{r}$<span aria-hidden="true">Br​</span> | 128    | K/V 块大小 |
| 共享内存使用                              | ~192KB | 接近上限   |

**不同隐藏维度**（Head Dimension）

| d   | 推荐 Bc | 推荐 Br | Q/K/V 基础 SRAM 使用 |
|-----|---------|---------|----------------------|
| 64  | 512     | 256     | 约 128KB             |
| 128 | 256     | 128     | 约 128KB             |
| 256 | 128     | 64      | 约 128KB             |

实际共享内存使用还取决于双缓冲、online softmax 状态和其他临时缓冲，需要结合具体 kernel 实现确认。

<div role="tabpanel" hidden="">

### 软件流水线设计

```text
┌───────────────────────────────────────────────────────────────┐
│           FlashAttention 软件流水线（双缓冲）                 │
├───────────────────────────────────────────────────────────────┤
│                                                                │
│  迭代 0:  [Load Q] → [Load K0,V0] → [Compute QK0] → [Update O0]│
│                                                                │
│  迭代 1:            [Load K1,V1] → [Compute QK1] → [Update O1] │
│                         ↑                                       │
│                         └── 与上一次计算重叠                   │
│                                                                │
│  迭代 2:                          [Load K2,V2] → [Compute QK2] │
│                                      ↑                           │
│                                      └── 与上一次计算重叠       │
│                                                                │
└───────────────────────────────────────────────────────────────┘
```

**优化技巧**：

1.  **双缓冲**：使用两组共享内存，交替加载和计算
2.  **张量内存引擎**（TME）
3.  **预计算 QK**：第一轮预先计算，主循环内 overlap softmax

<div role="tabpanel" hidden="">

### 寄存器压力管理

**主要寄存器消耗**：

- $O$<span aria-hidden="true">O</span> 累加器：$B_{c} \times d$<span aria-hidden="true">Bc​×d</span> 个 FP32 寄存器
- $P$<span aria-hidden="true">P</span> 概率矩阵：$B_{c} \times B_{r}$<span aria-hidden="true">Bc​×Br​</span> 个 FP32 寄存器
- 临时状态：$S$<span aria-hidden="true">S</span> tile、online softmax 的 running max/denominator 等

**优化策略**：

1.  减小 $B_{r}$<span aria-hidden="true">Br​</span>：降低寄存器压力（与 SRAM 约束冲突）
2.  减小每个线程负责的输出元素数量：降低 $O$<span aria-hidden="true">O</span> 累加器占用
3.  检查编译器寄存器使用报告，避免寄存器 spill 到局部内存

------------------------------------------------------------------------

## FlashAttention-2/3 改进

- FlashAttention-2
- FlashAttention-3

<div role="tabpanel">

### FlashAttention-2 改进：序列并行

**V1 问题**：

- 单 Block 只计算 Q 的一个块
- 长序列并行度不足

**FlashAttention-2 改进**：

- 在查询序列长度（Seq_Len_Q）上增加并行
- 不同 ThreadBlock 并行处理不同 Q 分块，每个 ThreadBlock 只需加载一次对应的 Q 块
- 内循环按键值序列长度（Seq_Len_KV）多次加载 K,V

<div role="tabpanel" hidden="">

### FlashAttention-3 改进：更细粒度流水线

**FlashAttention-3 新增特性**：

- 更细的 Tiling 粒度
- 多级流水线重叠
- 更好的占用率调控

------------------------------------------------------------------------

## 显存与性能收益趋势

### 理论显存占用对比（FP16）

| 序列长度 | 标准 Attention | FlashAttention | 降低倍数 |
|----------|----------------|----------------|----------|
| N=512    | 4MB            | 0.5MB          | 8x       |
| N=2048   | 68MB           | 2MB            | 34x      |
| N=4096   | 268MB          | 4MB            | 67x      |
| N=16384  | 4.3GB          | 16MB           | 268x     |

### 性能收益趋势（FP16）

| 序列长度 | 标准 Attention           | FlashAttention | 说明                         |
|----------|--------------------------|----------------|------------------------------|
| N=512    | 访存开销较低             | 收益有限       | 短序列下 kernel 开销占比更高 |
| N=2048   | 注意力矩阵访存压力增大   | 收益明显       | 分块和重计算开始体现优势     |
| N=4096   | O(N²) 显存与访存压力明显 | 收益显著       | 避免落地完整注意力矩阵       |
| N=16384  | 显存与访存压力很高       | 更适合长序列   | 实际性能需以目标硬件实测为准 |

上表用于说明随序列长度增长的收益趋势，不代表固定硬件或固定 kernel 的性能承诺。

------------------------------------------------------------------------

## 优化检查清单

### 块大小（Block Size）调优

**Bc, Br 是否匹配 SRAM 容量？**

- 共享内存使用 \< 90%
- 留出余量给临时缓冲和 online softmax 状态

**是否考虑隐藏维度**（Head Dimension）

- d=64: 更大的 Bc, Br
- d=256: 减小 Bc, Br

### 流水线优化

**是否使用双  缓冲？**

- 两组共享内存交替使用
- 加载与计算重叠

**张量内存引擎**（TME）

- 异步数据搬运
- 减少寄存器压力

### 寄存器管理

**是否溢出？**

- 检查编译器报告的寄存器使用
- 避免 spill 到局部内存

**占用率是否合理？**

- 使用 Moore Perf Compute 分析
- 平衡占用率与寄存器使用

------------------------------------------------------------------------

## 常见问题

Q1：FlashAttention 适合什么场景？

**答**：

- 更适合长序列和大 Batch 训练等注意力矩阵访存压力较高的场景。
- 短序列下 kernel 启动、调度和同步开销占比更高，是否使用 FlashAttention 需要结合实测判断。

Q2：为什么 FlashAttention 更快？

**答**：

1.  减少全局内存访问（IO 感知）
2.  避免存储 O(N²) 中间矩阵
3.  更好的数据局部性

Q3：精度是否有损失？

**答**：

- FlashAttention 数学上等价于标准 Attention
- 建议使用 FP32 累加器保证精度

------------------------------------------------------------------------

## 相关文档

- [GEMM/GEMV 优化](/musa-sdk/musa-sdk-doc-online/programming_guide/performance_tuning/gemm_gemv_optimization)：GEMM/GEMV 优化
- [Reduction 算法优化](/musa-sdk/musa-sdk-doc-online/programming_guide/performance_tuning/reduction_optimization)：Reduction 算法
- [计算优化](/musa-sdk/musa-sdk-doc-online/programming_guide/performance_tuning/compute_optimization)：计算优化
- [内存优化](/musa-sdk/musa-sdk-doc-online/programming_guide/performance_tuning/memory_optimization)：内存优化
