# Architecture Design Document: Basys3 FlashAttention

## 1. System Overview
This hardware accelerator has the goal of computing FlashAttention with a single systolic array pass. The mathematical definiton of Attention can be defined by:
$$
O = \text{softmax}(QK^\top)V
$$

## 2. Architectural Goals & Constraints
*   **Fused Tiling**: Execute online softmax updates incrementally without storing the full intermediate attention matrix $S$.
*   **Precision Support**: The accelerator runs a quantized INT8 model with $d$ embedding dimensions. 
*   **SRAM Footprint**: Unified column-major SRAM space with three double-buffers A, B and C, storing the tiles $Q_i, Q_{i+1}$, $K_i, K_{i+1}$, $V_i, V_{i+1}$ respectively.

## 3. Top-Level Hardware Architecture
The accelerator interfaces with a Host CPU via UART and manages internal execution using a dedicated controller, a Matrix Multiply Unit (MXU), and a Vector Processing Unit (VPU).

<!-- TODO: Add the top level diagram-->

## 4. Component Breakdown

### Matrix Multiply Unit (MXU)
*   **Responsibility**: Computes tile-level matrix multiplications ($Q_j K_i^T$).
*   **Microarchitecture**: $8 \times 8$ Systolic Array of MAC (Multiply-Accumulate) units supporting INT8 multiplication with INT32 accumulation.
*   **Dataflow**: The design uses an output-stationary dataflow, enabling the computation of an $M \times N$ tile for any $K$ dimension in an $M \times K \times N$ matrix multiplication using only $M \times N$ processing elements. Since $K \gg M \mid N$, this approach reduces hardware utilization by reducing the number of required processing elements or tiles. The main tradeoff is that the tile $Q_j$ requires a dedicated SRAM buffer, allowing it to be streamed for each GEMM operation instead of storing the weights locally within the processing elements. This design choice is particularly suitable for resource-constrained boards such as the Basys3, where DSP resources are limited and memory is comparatively abundant.

### Vector Processing Unit (VPU)
*   **Responsibility**: Computes online element-wise row statistics ($m_j$, $l_j$, and $O_j$).
*  **Microarchitecture**: INT8 to FXP12 convertion unit, exponential calculation unit $e^x$ and registers to keep the statistics.

## 5. Execution Dataflow
$$
\begin{aligned}
&\textbf{for each query tile } j: \\[4pt]
&\qquad \text{Load } Q_j \\[8pt]
&\qquad \textbf{for each key/value tile } i: \\[4pt]
&\qquad\qquad \text{Load } K_i, V_i \\[8pt]
&\qquad\qquad s_{ji} = q_j k_i^T \\[8pt]
&\qquad\qquad m_j = \max(m_j, s_{ji}) \\[8pt]
&\qquad\qquad l_j =
e^{m_{j-1}-m_j}*l_{j-1}
+
e^{s_{ji}-m_j} \\[8pt]
&\qquad\qquad O_j =
\frac{e^{m_{j-1}-m_j}*l_{j-1}}{l_j}O_{j-1}
+
\frac{e^{s_{ji}-m_j}}{l_j}v_j
\end{aligned}
$$

## 6. Register-Transfer Level (RTL) & Deployment Target
*   **Target Device**: Basys3 xc7a35t.
*   **HDL Standard**: SystemVerilog (IEEE 1800-2017).
*   **Clock Target**: 100MHz
