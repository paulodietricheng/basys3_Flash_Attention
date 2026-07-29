# Architecture Design Document: Basys3 FlashAttention

<!-- fa_ctrl does not need to know mxu_done, just mxu_start -->
<!-- fa_ctrl does not need to receive mxu_cmd, only output mxu_cmd -->
<!-- fa_ctrl only needs to tell the dma how to fetch the data, receive the command from the cpu, with sq_len, fa_start 
and output fa_done and tell when to fetch the next q tile. The FSM should be IDLE, fetch Qi, Fetch KiVi, Compute Attention
while Fetching Ki'Vi', Output ON while fetching Qi', FA_DONE-->

## 1. System Overview
This hardware accelerator has the goal of computing FlashAttention with a single systolic array pass. The mathematical definiton of Attention can be defined by:

$$
O = \text{softmax}(QK^\top)V
$$

It is divided in 6 main modules: Control, DMA, SRAM, SRAM-CTRL, Matrix Multiplication Unit (MXU), Vector Processing Unit
(VPU).

![Block Diagram](images/fa_bd.png)

## 2. Architectural Goals & Constraints
*   **Fused Tiling**: Execute online softmax updates incrementally without storing the full intermediate attention matrix $S$.
*   **Precision Support**: The accelerator runs a quantized INT8 model with $d$ embedding dimensions. 
*   **SRAM Footprint**: Unified column-major SRAM space with three double-buffers A, B, C and D, storing the tiles $Q_i, Q_{i+1}$, $K_i, K_{i+1}$, $V_i, V_{i+1}$, $O_i, O_{i+1}$ respectively.

## 3. Top-Level Hardware Architecture
The accelerator interfaces with a Host CPU via UART and manages internal execution using a dedicated controller, a Matrix Multiply Unit (MXU), and a Vector Processing Unit (VPU).

## 4. Component Breakdown

### Matrix Multiply Unit (MXU)
*   **Responsibility**: Computes tile-level matrix multiplications ($Q_j K_i^T$).
*   **Microarchitecture**: $8 \times 8$ Systolic Array of MAC (Multiply-Accumulate) units supporting INT8 multiplication with INT32 accumulation.
*   **Dataflow**: The design uses an output-stationary dataflow, enabling the computation of an $M \times N$ tile for any $K$ dimension in an $M \times K \times N$ matrix multiplication using only $M \times N$ processing elements. Since $K \gg M \mid N$, this approach reduces hardware utilization by reducing the number of required processing elements or tiles. The main tradeoff is that the tile $Q_j$ requires a dedicated SRAM buffer, allowing it to be streamed for each GEMM operation instead of storing the weights locally within the processing elements. This design choice is particularly suitable for resource-constrained boards such as the Basys3, where DSP resources are limited and memory is comparatively abundant.

### Vector Processing Unit (VPU)
*   **Responsibility**: Computes online element-wise row statistics ($m_j$, $l_j$, and $O_j$).
*   **Microarchitecture**: INT8 to FXP12 convertion unit, exponential calculation unit $e^x$ and registers to keep the statistics.

## 5. Execution Dataflow

![FlashAttention algorithm](images/fa_eq.png)

## 6. Register-Transfer Level (RTL) & Deployment Target
*   **Target Device**: Basys3 xc7a35t.
*   **HDL Standard**: SystemVerilog (IEEE 1800-2017).
*   **Clock Target**: 100MHz
# Overview
This system is a FlashAttention [^1] Accelerator targeting the basys3 [^2] board designed as a learning experiment and intro 
to transformers accelerators. It uses a single output-stationary systolic array [^3] pass with the goal of computing:

$$
O = \text{softmax}(QK^\top)V
$$

# Architecture
The design consists of 6 main modules: Controller, DMA, SRAM Controller, SRAM, Matrix Multiplication Unit (MXU), Vector Processing Unit
(VPU). The design runs on a quantized INT8 model, with convertion for FXP12 for the VPU.

![Top Block Diagram](images/fa_bd.png)


## Control
Is responsible for the communication between the CPU and the accelerator. It also sends DMA requests, MXU requests and acts as a tile scheduler. 

### Interface
#### INPUTS
|signal name  |Description|
|--|--|
|fa_start     |Start FlashAttention computation|
|sq_len     |Token sequence length|
|dma_done|Full data transfer between HBM and SRAM done|
|mxu_done   |Signal GEMM done|

#### OUTPUTS
|signal name  |Description|
|--|--|
|fa_done    |Computation done|
|mxu_start  |Start the GEMM systolic array|
|mxu_cmd    |Pass dimensions M, N, K of the M x K x N GEMM, row and column offset for tiled matmul|
|dma_rq     |Pass number of active channels, Transfer direction, Base address, Destination address, Byte count|

## MXU

![MXU Block Diagram](images/mxu_bd.png)

This module is responsible for intaking 2 matrices A and B with respective $M \times K$ and $K \times N$ dimensions and produce an $M \times N$ output. The precisions of the operands are INT8, and the accumulator has INT32 precision. 

Additionaly, it also outputs the maximum `row_max` and sum `row_sum` per row at every cycle. (`row_sum` still to be implemented)

The latency for an output-stationary (OS) $M \times K \times N$ can be defined by the following formula [^4]:

$$
T_{cyc} = M + N + K -2
$$

However, to account for the internal DSP latency [^5] and computation of `row_max` and `row_sum`, `DSP_LAT` and another instance of `N` must be added. Thus, the total latency for the computation is given by:

$$
T_{cyc} = M + 2N + K -2 + \text{DSP_LAT}
$$

### Control
Finite state machine controlling `m_IDLE`, `m_CLEAR`, `m_STREAM`, `m_DRAIN` and `m_DONE` states. Latches `mxu_cmd` and controls which dimension `k_idx` is being fetched from the SRAM and when to stop fetching. Also instantiates a counter for cycle-acurate detection of when the GEMM is complete, which is when `counter == T_cyc`.

|state  |description|
|-|-|
|m_IDLE|Waits for `mxu_start`|
|m_CLEAR|Cleans all residual PEs and sets the starting `k_idx` to be fetched for each input matrix|
|m_STREAM|Enables the systolic array, tells the SRAM buffer it is being read, and increments `k_idx` while `k_idx < K`, and then moves on|
|m_DRAIN|Stops reading from the SRAM and 0s are streamed through the array, which keeps computing until the GEMM is complete|
|m_DONE|Outputs `mxu_done` and goes to `m_IDLE`|

### Operand Handler
Forwards the index request to the SRAM_CTRL, where it is translated into an address and slices the incoming bus of operands.

### Operand Skewer
Receives one full operand dimension per cycle, and skews line `i` by `i cycles` using shift registers.

### Systolic Array

Computes the output-stationary GEMM $C =A \times B$ using a grid of `SA_ROWS` by `SA_COLS` Processing Elements (PE), connected by a fabric. Matrix A is fed from left to right, while matrix B is fed top to bottom, and the output accumulator is stationary to each processing element. 
The design uses an output-stationary dataflow, enabling the computation of an $M \times N$ tile for any $K$ dimension in an $M \times K \times N$ matrix multiplication using only $M \times N$ processing elements. Since $K \gg M \mid N$, this approach reduces hardware utilization by reducing the number of required processing elements or tiles. The main tradeoff is that the tile $Q_j$ requires a dedicated SRAM buffer to allow it to be streamed for each GEMM operation instead of storing the weights locally within the PEs. This design choice is particularly suitable for resource-constrained boards such as the Basys3, where DSP resources are limited and memory is comparatively abundant.

#### Processing Element (PE)
Intakes `in_a` and `in_b` and computes `c = c + (in_a * in_b)`, and also evaluates wether the forwarded result from the left processing element is greater than the accumulator of this PE, and forwards the larger one to the next PE on the right.

## VPU (To be implemented)
Has the goal of applying the online softmax algorythim to the Attention Score $S$ produced by the MXU.

It does it by updating the three statistics $m_j$, $l_j$ and $o_j$ for each $j$ row.

![Statistics update equations](images/fa_st.png)

It converts $S$ to FXP12 precision, and implements the $e^x$ function using CompressedLut 

@inproceedings{compressedlut_fpga,
    author = {Khataei, Alireza and Bazargan, Kia},
    title = {CompressedLUT: An Open Source Tool for Lossless Compression of Lookup Tables for Function Evaluation and Beyond},
    year = {2024},
    publisher = {Association for Computing Machinery},
    address = {New York, NY, USA},
    url = {https://doi.org/10.1145/3626202.3637575},
    doi = {10.1145/3626202.3637575},
    booktitle = {Proceedings of the 2024 ACM/SIGDA International Symposium on Field Programmable Gate Arrays},
    pages = {2-11},
    numpages = {10},
    location = {Monterey, CA, USA},
    series = {FPGA '24}
}

## SRAM (currently not unified, will be unified in v2)
Unified SRAM buffer for storing the $Q_j$, $K_j$, $V_j$ and $O_j$ tiles on chip. (V and O to be added)

It uses a double-buffer approach to allow for simultaneous fill and feed of matrices. Only the SRAM Controller knows of the existence of the double buffers, controlling when they switch. 

### Interface
#### INPUTS
|signal name  |Description|
|--|--|
|din_A a and b, dinB a and b. TBA: din_C, din_D   |32 bit input data buses|
|bufA_wr_addr a and b, bufB_wr_addr a and b. TBA bufC_wr_addr a and b, bufD_wr_addr a and b    |Write addresses|
|bufA_rd_addr a and b, bufB_rd_addr a and b. TBA bufC_rd_addr a and b, bufD_rd_addr a and b|Read addresses|
|bufA_rd_ram, bufB_rd_ram. TBA bufA_rd_ram, bufB_rd_ram|Select which RAM is being read from in the double buffer (0 = RAM0, 1 = RAM1)|

#### OUTPUTS
|signal name  |Description|
|--|--|
|bufA_dout a and b, bufB_dout a and b. TBA bufC_dout a and b, bufD_dout a and b|32 bit output data busses|

## SRAM Controller
C


