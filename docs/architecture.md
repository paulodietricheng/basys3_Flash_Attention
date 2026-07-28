# Architecture Design Document: Basys3 FlashAttention

## 1. System Overview
A hardware accelerator designed to compute exact Attention ($O = \text{softmax}(QK^T)V$)
while minimizing $O(N^2)$ memory traffic to High Bandwidth Memory (HBM). By leveraging a 
fused online softmax tiled pipeline, the architecture replaces global memory round-trips 
with localized Static Random-Access Memory (SRAM) data reuse.

## 2. Architectural Goals & Constraints
*   **Fused Tiling**: Execute online softmax updates incrementally without storing the full intermediate attention matrix $S = QK^T$.
*   **Precision Support**: The accelerator runs a quantized INT8 model with 16 embedding dimensions. 
*   **SRAM Footprint**: Constrained on-chip SRAM capacity requiring optimal block sizes $B_r$ (row tile) and $B_c$ (column tile).

## 3. Top-Level Hardware Architecture
The accelerator interfaces with a Host CPU via UART and manages internal execution using a dedicated controller, a Matrix Multiply Unit (MXU), and a Vector Processing Unit (VPU).

<!-- TODO: Add the top level diagram-->

## 4. Component Breakdown

### Matrix Multiply Unit (MXU)
*   **Responsibility**: Computes tile-level matrix multiplications ($Q_j K_i^T$).
*   **Tech Stack / Microarchitecture**: $8 \times 8$ Systolic Array of MAC (Multiply-Accumulate) units supporting INT8 multiplication with INT32 accumulation.
*   **Dataflow**: Output-stationary dataflow optimized for structural GEMM operations.

### Vector Processing Unit (VPU)
*   **Responsibility**: Computes online element-wise row statistics ($m_j$, $l_j$, and $\tilde{O}_j$).
*  <!-- **Microarchitecture**: Pipelined Exponential units ($e^x$), FP32 accumulators, and reciprocal/division units. -->
*   <!-- **Throughput**: Coupled tightly to the MXU output rate to clear values without stall cycles. -->

## 5. Memory Hierarchy & Mathematical Tiling
Data movement is dictated by localized SRAM capacity limits. The block constraints are derived using the dimension variables $d$ (head dimension), 
$B_r$ (row block size), and $B_c$ (column block size).

### Hardware Tiling Constraints
To store tiles of $Q, K, V$ and intermediate statistics safely within an $M$-byte SRAM capacity, the block allocations must satisfy:

$$B_r \cdot d + B_c \cdot d + B_c \cdot d + B_r \cdot d \le M$$

Simplifying the memory boundary calculation:

$$d(2B_r + 2B_c) \le M$$

### Execution Dataflow
```markdown

```

<!-- add algorythim -->

## 6. Register-Transfer Level (RTL) & Deployment Target
*   **Target Device**: Basys3 xc7a35t.
*   **HDL Standard**: SystemVerilog (IEEE 1800-2017).
*  <!-- **Clock Target**: $1.2\text{ GHz}$ operational frequency under worst-case PVT corners. -->

## 7. Architectural Decision Records (ADRs)
*   **ADR 001: Online Softmax Hardware Implementation Choice**
    *   **Context**: Classic softmax requires materializing the full row to find the maximum value, blocking pipelining.
    *   **Decision**: Adopt the FlashAttention online tracking method using re-scaling factors:
    $$\tilde{A}_{ij} = e^{S_{ij} - m_{\text{new}}}$$
    *   **Consequences**: Eliminates large $O(N^2)$ tracking registers; requires a dedicated VPU rescaling pipeline.
