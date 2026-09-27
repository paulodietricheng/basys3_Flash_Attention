![AI](https://img.shields.io/badge/FlashAttention-Accelerator-green) ![Board](https://img.shields.io/badge/board-Basys3-orange) ![Tool](https://img.shields.io/badge/tool-Vivado-red) ![HDL](https://img.shields.io/badge/HDL-SystemVerilog-blue)

# Flash Attention FPGA Accelerator

Hardware implementation of an attention accelerator targeting the **Digilent Basys 3 FPGA**, with a complete RTL datapath, systolic matrix multiplication unit, on-chip memory system, UART command interface, PC client, verification infrastructure, and automated Vivado build flow.

The project is designed as an end-to-end hardware system rather than an isolated compute block: matrices are transferred from a host PC to the FPGA over UART, stored in on-chip BRAM, processed by the accelerator, and returned to the host for verification.

## Overview

The accelerator implements a tiled attention datapath built around an **output-stationary systolic matrix multiplication unit (MXU)** and supporting vector-processing logic.

The complete system includes:

- SystemVerilog RTL for the attention accelerator
- Systolic matrix multiplication unit
- Vector processing unit
- Four internal dual-port BRAMs
- UART RX/TX interface
- Binary command protocol with CRC checking
- Host-accessible Q, K, V, and O memories
- Python PC client
- Basys 3 top-level integration
- Vivado Tcl project/build automation
- SystemVerilog, Python, C++, Verilator, and XSim-oriented verification infrastructure

### Current configuration

| Parameter                 |                  Value |
| ------------------------- | ---------------------: |
| FPGA                      | Xilinx Artix-7 XC7A35T |
| Development board         |       Digilent Basys 3 |
| Fmax                      |             \~83.3 MHz |
| LUT                       |                  10904 |
| FF | 30509 |
| BRAM | 4 |
| DSP | 73 |
| UART                      |       115200 baud, 8N1 |
| Input datatype            |                   INT8 |
| Embedding dimension       |                     16 |
| Supported sequence length |                  8–256 |
| Sequence granularity      |         Multiples of 8 |
| Matrix transport          |                   UART |
| Host interface            |                 Python |

> **Note**
>
> The current EXP and reciprocal operations are simplified placeholder arithmetic. The hardware therefore validates the accelerator architecture, datapath, memory system, control flow, and FPGA communication infrastructure, but is not yet intended to reproduce numerically accurate softmax attention.

---

# Architecture

At a high level:

![Top Block Diagram](images/fa_bd.png)

The PC communicates with the board through the Basys 3's onboard USB/UART bridge.

Input matrices are written into Q, K, and V memories. Once loaded, the host issues a `START` command. The hardware executes the attention datapath and stores the resulting matrix in O memory, where it can be read back by the host.

The host interface is only granted access to accelerator memory while the compute engine is idle.

---

# Repository Structure

```text
.
├── rtl/                  # Synthesizable SystemVerilog
│
├── tb/                   # SystemVerilog testbenches
│
├── host/
│   ├── fa_client.py      # PC-side UART client
│
├── scripts/
│
├── constraints/          # Basys 3 XDC constraints
│
├── fixtures/             # Verification vectors
│
├── examples/
|
├── tests/                # Regression infrastructure
│
├── results/              # Verification/build results
│
├── PROTOCOL.md           # UART protocol definition
│
└── README.md
```

---

# Quick Start

## Requirements

For FPGA implementation:

- AMD/Xilinx Vivado
- Artix-7 device support
- Digilent Basys 3

For host communication:

- Python 3
- `pyserial`

For the full regression suite:

- Python 3
- `make`
- C++ compiler

---

# 1. Create the Vivado Project

Clone the repository:

```bash
git clone <repository-url>
cd <repository-name>
```

Open Vivado without creating a project.

From the Vivado Tcl console:

```tcl
source scripts/create_project.tcl
```

The script automatically:

- creates the Vivado project
- selects the XC7A35T device used by the Basys 3
- adds RTL sources in the correct compilation order
- adds the Basys 3 constraints
- configures `basys3_top` as the synthesis top
- configures `tb_uart` as the simulation top
- configures required simulation fixtures

The generated project is located under:

```text
vivado_project/
```

---

# 2. Run RTL Simulation

In Vivado:

```text
Run Simulation → Run Behavioral Simulation
```

If required, enter:

```tcl
run all
```

A successful UART integration test should finish with:

```text
PASS UART load and readback bank=0
PASS UART load and readback bank=1
PASS UART load and readback bank=2
PASS UART end-to-end: N=8, actual MXU, internal BRAM, exact O match
```

The testbench does **not** bypass the hardware by initializing the DUT memories hierarchically.

---

# 3. Build the FPGA Bitstream

After simulation succeeds:

```tcl
source scripts/build_bitstream.tcl
```

The script runs:

1. Synthesis
2. Implementation
3. Timing analysis
4. DRC
5. Bitstream generation

The resulting bitstream is typically located at:

```text
vivado_project/fa_basys3.runs/impl_1/basys3_top.bit
```

The build script checks setup/hold timing and implementation status before producing the final hardware image.

---

# 4. Program the Basys 3

Connect the board using the **Micro-USB PROG/UART J4 connector**.

In Vivado:

```text
Hardware Manager
→ Open Target
→ Auto Connect
→ Program Device
```

Select:

```text
basys3_top.bit
```

No external UART adapter or soft processor is required. The Basys 3 already contains the required USB/UART bridge.

### LED Status

| LED | Meaning               |
| --- | --------------------- |
| LD0 | Accelerator busy      |
| LD1 | Computation completed |
| LD2 | Protocol/core error   |
| LD3 | Reset released        |

The center push button resets communication and compute control.

---

# 5. Install the Host Client

From the repository root:

```bash
python -m pip install -r host/requirements.txt
```

Find connected serial devices:

```bash
python host/fa_client.py ports
```

Determine which COM port corresponds to the Basys 3.

For example:

```text
COM6
```

---

# 6. Test Communication

Check accelerator status:

```bash
python host/fa_client.py --port COM6 status
```

Run a basic memory/UART test:

```bash
python host/fa_client.py --port COM6 smoke
```

The smoke test:

1. Reads existing Q-memory contents
2. Writes a test pattern
3. Reads the pattern back
4. Verifies it
5. Restores the original values

---

# 7. Run the Accelerator

A complete test fixture can be executed with:

```bash
python host/fa_client.py --port COM6 run-fixture fixtures/dummy_fixed/000
```

The client:

1. Resets the accelerator
2. Loads Q
3. Loads K
4. Loads V
5. Reads inputs back for verification
6. Starts computation
7. Polls accelerator status
8. Reads O
9. Compares the FPGA result against the expected output

Successful execution prints:

```text
PASS input readback and exact O comparison.
```

---

# Running Custom Matrices

Example input:

```text
examples/input_8.json
```

The expected format is:

```json
{
    "Q": [...],
    "K": [...],
    "V": [...]
}
```

Each matrix must have shape:

```text
N × 16
```

where:

```text
8 <= N <= 256
N % 8 == 0
```

Elements are signed INT8 values:

```text
-128 to 127
```

Run:

```bash
python host/fa_client.py \
    --port COM6 \
    run-matrices examples/input_8.json \
    --output result.json
```

The client automatically handles:

- matrix layout conversion
- byte packing
- UART packet generation
- memory loading
- readback verification
- accelerator command sequencing
- completion polling
- output conversion

The resulting matrix and accelerator status are written to:

```text
result.json
```

You do **not** need to synthesize or reprogram the FPGA when changing matrices.

---

# UART Protocol

The FPGA exposes a binary packet protocol supporting:

```text
WRITE
READ
START
STATUS
RESET
```

Host access is available for:

```text
Q
K
V
O
```

Commands include validation and CRC checking before memory writes are committed.

Memory commands and duplicate `START` operations are rejected while the accelerator is busy, while `STATUS` and `RESET` remain available.

For the full packet format, see:

```text
PROTOCOL.md
```

---

# Verification

The design has been tested at multiple levels.

## Compute Regression

The compute regression exercises the real MXU, VPU, and internal BRAM architecture across multiple configurations.

The regression currently covers:

- 160 compute jobs
- 45,848 completed matrix blocks
- 69,120 output payload words
- multiple memory layouts
- dummy and reference arithmetic configurations

## UART / System Integration

The complete serial path has also been tested through the actual Python client against RTL simulation.

Coverage includes:

- Q/K/V loading
- memory readback
- exact accelerator output comparison
- sequence lengths including 8, 16, and 256
- custom matrix packing
- CRC rejection
- invalid command rejection
- invalid memory ranges
- malformed packets
- packet truncation
- UART frame errors
- protocol resynchronization
- sequence-number wrap
- commands issued while busy
- reset during active computation
- memory preservation across compute reset
- production 115200-baud operation
- baud-rate variation

---

# Important Implementation Notes

The compute system runs at approximately:

```text
83.3 MHz
```

UART communication runs at:

```text
115200 baud
```

UART logic uses clock enables rather than introducing a separate generated clock.

The receive path includes a two-flop synchronizer for the asynchronous serial input.

Board reset asserts asynchronously and is synchronously released through a multi-register synchronization chain.

Internal compute paths remain fully timed by the implementation constraints.

---

# Host Transfer Performance

UART transfer speed is intentionally separate from accelerator compute performance.

At 115200 baud, the maximum raw payload rate is approximately:

```text
11.52 kB/s
```

For large matrices, host-to-FPGA transfer therefore takes substantially longer than the accelerator's internal computation.

The Python client reports accelerator cycle counts independently so compute latency can be measured without confusing it with UART transfer overhead.

---

# Current Limitations

The current implementation is primarily a **hardware architecture and systems-integration prototype**.

Notable limitations include:

- EXP is currently represented by simplified placeholder arithmetic
- reciprocal is currently represented by simplified placeholder arithmetic
- UART bandwidth limits host transfer performance
- no DMA engine
- no double buffering
- memory transfer and compute do not overlap

---

# Next steps

V1

- Replace the placeholders exp and rcp by their propper implementations

V2

- Implement ping-pong buffering for loading matrices while they compute.&#x20;
- DMA Based memory management

V3

- resource and timing optimization
- ASIC-oriented synthesis and physical implementation

---

# References

- Digilent Basys 3 Reference Manual
  [https://reference.digilentinc.com/\_media/reference/programmable-logic/basys-3/basys3_rm.pdf](https://reference.digilentinc.com/_media/reference/programmable-logic/basys-3/basys3_rm.pdf)

- Digilent Basys 3 Master XDC
  [https://github.com/Digilent/digilent-xdc/blob/master/Basys-3-Master.xdc](https://github.com/Digilent/digilent-xdc/blob/master/Basys-3-Master.xdc)

- pySerial Documentation
  [https://pyserial.readthedocs.io/en/latest/pyserial_api.html](https://pyserial.readthedocs.io/en/latest/pyserial_api.html)

- AMD Vivado Tcl Command Reference
  [https://docs.amd.com/r/en-US/ug835-vivado-tcl-commands/get_timing_paths](https://docs.amd.com/r/en-US/ug835-vivado-tcl-commands/get_timing_paths)

---

## Project Status

The core accelerator, internal memories, UART protocol, host interface, and regression infrastructure are implemented and operational in simulation.

FPGA synthesis, timing closure, and physical-board behavior should always be independently verified for the exact Vivado version and target configuration being used.
