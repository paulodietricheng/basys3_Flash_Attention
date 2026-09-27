# Basys 3 attention accelerator with PC communication

This is a complete source package for a NEW Vivado project. It includes the
actual corrected MXU, VPU, four internal BRAMs, UART transport, packet command
controller, board top, XDC constraints, Python PC client, fixtures and tests.
Do not combine it with older module copies from the previous project.

Hardware top: **basys3_top**. Simulation top: **tb_uart**.

The RTL/software path has passed simulation, including bit-level UART and
the actual Python client. This environment does not have Vivado or a physical
Basys 3: synthesis, device fit, timing closure and physical board execution
have NOT been validated. The supplied build script produces those reports
locally and stops on negative internal timing slack. No prebuilt bitstream is
included. Default EXP/RCP remain dummy functions, not mathematical softmax.

## 1. Create and simulate the new Vivado project

Extract this ZIP to a simple path without spaces, for example `C:/fpga/fa_pc`.
The root should contain rtl, tests, scripts, host, constraints and fixtures.
Case 000 is already included, so the first simulation needs no Python setup.

Open Vivado with no project open. Enter in the Tcl Console:

```tcl
source C:/fpga/fa_pc/scripts/create_project.tcl
```

The script creates vivado_project/fa_basys3.xpr for xc7a35tcpg236-1, adds all
required sources in package-first order, adds the Basys 3 pin constraints,
selects basys3_top for hardware and tb_uart for simulation, and sets the fixture
path automatically. If you run it again, open the existing XPR rather than
overwriting it. The project references extracted files; keep that folder.

Select **Run Simulation -> Run Behavioral Simulation**. The configured runtime
is `all`. If the simulator is paused, enter `run all` in its Tcl Console.

Expected final output:

```text
PASS UART load and readback bank=0
PASS UART load and readback bank=1
PASS UART load and readback bank=2
PASS UART end-to-end: N=8, actual MXU, internal BRAM, exact O match
```

This test loads ALL Q/K/V words over the simulated serial RX pin, reads each
word back, issues START, polls STATUS and compares returned O against the
independent fixture. It does not initialize DUT memory hierarchically. Its
serial divider is accelerated for simulation (8 clocks/bit); the board wrapper
retains 100 MHz and 115200 baud. Expected simulated duration is about 22 ms.

The same tb_uart source passed in Verilator; XSim compatibility is still to be
confirmed by your run. If Vivado reports an error, use the first compilation
or assertion error as the starting point, rather than the final wrapper error.

## 2. Build and program the board

After the simulation passes, close simulation and run in the project's Tcl
Console:

```tcl
source C:/fpga/fa_pc/scripts/build_bitstream.tcl
```

This runs synthesis and implementation, reports utilization/timing/DRC, checks
setup and hold slack, and generates `basys3_top.bit` if successful. It requires
your Vivado installation to include Artix-7 support. Treat resource overflow,
timing failure or DRC failures as issues to fix before hardware use; simulation
passing is not evidence that the chosen device meets 100 MHz.

Connect the Basys 3's **Micro-USB PROG/UART connector J4** using a data-capable
cable, power the board, then use **Hardware Manager -> Open Target -> Auto
Connect -> Program Device**, selecting the generated bitstream. Its usual path:

```text
vivado_project/fa_basys3.runs/impl_1/basys3_top.bit
```

Do not use the board's USB-A host socket for this PC serial connection. The
board already provides the USB/UART bridge. You do not need a UART adapter,
MicroBlaze, or an operating system on the FPGA.

LED mapping:

| LED | Meaning |
| --- | --- |
| LD0 | Accelerator busy |
| LD1 | Completion latched; clears on START or RESET |
| LD2 | Protocol/core error latched; clears on RESET |
| LD3 | Board reset released |

The center button resets the link and compute control. It does not erase BRAM.
When the bitstream changes, recheck the Python client's status response before
loading a job. Configuration is volatile unless you separately program flash.

## 3. Connect from the PC

Open PowerShell in the extracted package root and install the one dependency:

```powershell
python -m pip install -r host/requirements.txt
python host/fa_client.py ports
```

Find the board's COM port in that list or Windows Device Manager. Substitute
your port for COM5 in the commands below. If no port appears, check the cable,
board power and FTDI virtual COM-port driver. Close other serial terminals
using the port. The default connection is 115200 baud, 8N1, no flow control.
The protocol is binary: typing command names into a text terminal will not
execute them. Use the supplied Python client.

```powershell
python host/fa_client.py --port COM5 status
python host/fa_client.py --port COM5 smoke
python host/fa_client.py --port COM5 run-fixture fixtures/dummy_fixed/000
```

`status` prints firmware identity/capabilities and busy/done/error flags.
`smoke` saves four Q words, writes a pattern, reads it back and restores the
original words on a functioning link. `run-fixture` resets compute, loads and
verifies all Q/K/V data, starts N=8, waits and checks O exactly. It should print:

```text
PASS input readback and exact O comparison.
```

If communication times out, first check board programming, COM port and baud.
The client never silently retries START: a lost acknowledgment can leave a job
already running. Query status or recover with:

```powershell
python host/fa_client.py --port COM5 reset
```

Then rerun the fixture (which reloads inputs). The reset command aborts an
active job, preserves SRAM, and clears latched completion/error status.

## 4. Run your own Q/K/V matrices

An example input is supplied in examples/input_8.json. JSON keys are Q, K and
V, each an N x 16 array of signed integers from -128 to 127. N must be a
multiple of eight from 8 to 256. This is the current INT8 input format; do not
pass floating-point embeddings without choosing a quantization scheme first.

```powershell
python host/fa_client.py --port COM5 run-matrices examples/input_8.json --output result.json
```

The client handles Q/K dimension-major layout, V row-major layout, byte packing,
loading, input readback verification, command sequencing and O conversion.
result.json contains the signed N x 16 output matrix and status/cycle count.
Default arithmetic is still placeholder EXP(x)=x+1 and RCP(x)=x-2. Its results
are useful for transport/flow verification, not numerical attention accuracy.

There is no need to rebuild or reprogram the FPGA for each new set of matrices.
At 115200 baud the payload rate is 11520 bytes/s. Loading 12 KiB of Q/K/V takes
at least 1.07 s; verifying input readback adds another 1.07 s, plus packet/USB
overhead. Returning a full 4 KiB O adds about 0.36 s. Measure the reported
busy-cycle count separately from end-to-end PC transfer time.

## Design organization

| File/module | Responsibility |
| --- | --- |
| basys3_top | Physical pins, power-on/button reset, LEDs |
| fa_uart_top | Connects UART controller to the complete accelerator |
| uart_rx / uart_tx | Synchronized RX and 8N1 serial byte transport |
| uart_command | Framing, CRC, validation, bounded transfers, status/reset |
| fa_top | Idle-only host SRAM access plus existing attention compute |
| sram / bram | Four internal 1024x32 dual-port memories |
| host/fa_client.py | Framed serial client, matrix packing, fixture verification |

The compute core's new host port arbitrates one word at a time while idle.
An accepted START has priority. UART packets are validated before any writes.
The protocol allows WRITE to Q/K/V, READ from Q/K/V/O, START, STATUS and RESET.
Memory commands and duplicate START are rejected while busy. STATUS and RESET
remain available. There is one outstanding packet at a time, no DMA, no double
buffering and no transfer/compute overlap. Full field definitions are in
PROTOCOL.md. O's earlier direct readback port is retained at fa_top and tied
off in the board wrapper; the serial controller uses the generic host port.

The SRAM/compute clock is 83 MHz throughout. UART uses counters/clock enables,
not a separate generated clock. RX has a two-flop synchronizer. Board reset
asserts asynchronously and releases through a four-register chain. Constraints
except only external asynchronous RX/reset and slow TX/LED endpoints; internal
compute paths remain timed. Clock/baud values must be changed consistently if
you later add clock division or alter the input clock.

## Tests and results

This package's final source passed:

- The existing 160-job compute regression with real MXU/internal BRAM, across
  both memory layouts and dummy/reference arithmetic (45,848 completed matrix
  blocks and 69,120 payload output words). The host port is disabled in these
  regressions to check the compute path remains unchanged.
- The actual Python client against a C++ bit-level UART harness and the full
  RTL. It checks input loading/readback and exact output for N=8,16,256,8
  consecutively, plus a separate custom-matrix packing/reference test.
- CRC rejection with unchanged memory; bad opcodes, bank/address/count and
  sequence lengths; oversized/truncated packets; frame errors; resynchronization;
  sequence wrap; busy rejection; reset during compute with memory retention.
- Production 83.3 MHz/115200 baud divider operation and approximately +/-1%
  sender baud variation.
- The standalone SystemVerilog tb_uart selected in the new Vivado project.

The current Q16 reference's maximum observed floating-point error remains
0.0028042096553164697 before INT8 conversion. Q16 true-function EXP/RCP are
simulation-only replacements; they are not included in the hardware file list.

Logs/summaries are in results/. Existing unused row_max/row_sum pin warnings
and the fixed-geometry result_lat width warning remain from the trusted MXU.
Do not interpret a passing simulation as a synthesis/timing/physical-board test.

To rerun everything outside Vivado, install Python 3, Verilator with timing
support, make and a C++ compiler, then:

```sh
python tests/run_all.py
```

Individual entry points:

```sh
python tests/run.py                         # compute + BRAM regressions
python tests/test_serial.py                 # real Python client + UART RTL
python tests/test_serial.py --production-baud
python tests/run_uart_sv.py                 # standalone SV serial testbench
```

The simulation harness substitutes the PC-side wire driver only. It does not
replace the FPGA UART, command controller, SRAM, MXU, VPU or writer. More
fixtures are generated automatically by these scripts, or explicitly with
`python tests/generate_cases.py`. The ZIP includes only case 000 initially.

## Sources for board/tool details

- Digilent Basys 3 reference manual (J4 shared programming/UART interface):
  https://reference.digilentinc.com/_media/reference/programmable-logic/basys-3/basys3_rm.pdf
- Digilent master pin constraints:
  https://github.com/Digilent/digilent-xdc/blob/master/Basys-3-Master.xdc
- pySerial API:
  https://pyserial.readthedocs.io/en/latest/pyserial_api.html
- AMD timing-path Tcl reference:
  https://docs.amd.com/r/en-US/ug835-vivado-tcl-commands/get_timing_paths
