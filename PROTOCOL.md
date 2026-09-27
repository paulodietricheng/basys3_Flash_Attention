# UART protocol v1

Physical link: 115200 baud, eight data bits, no parity, one stop bit (8N1),
no hardware/software flow control. Basys 3 clock: 100 MHz. Receiver pin B18;
transmitter pin A18. Every multibyte numeric field and 32-bit SRAM word uses
big-endian byte order. UART itself sends bits within a byte least-significant
bit first, as usual; uart_rx/uart_tx handle that detail.

## Framing

Request:

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 2 | Magic A5 5A |
| 2 | 1 | Sequence ID |
| 3 | 1 | Command |
| 4 | 2 | Payload length in bytes |
| 6 | length | Payload |
| 6+length | 2 | CRC |

Response has the same format, with magic 5A A5 and status in place of command.
Sequence ID is echoed. It wraps modulo 256. Request payload maximum is 261
bytes; response payload maximum is 256 bytes. One request may be outstanding
at a time. Wait for its complete response before sending another request.
There is no unsolicited completion message; STATUS reports sticky completion.

CRC-16/CCITT-FALSE: polynomial 0x1021, initial value 0xFFFF, no reflection,
no final XOR. Cover sequence ID, command/status, length and payload. Exclude
magic and the CRC bytes. Send CRC high byte first. Test vector "123456789"
produces 0x29B1. Entire requests are received and verified before any SRAM
write or start is executed. This protects against malformed packets; it is
not a promise of transaction rollback across a board reset or power failure.

## Commands

| Code | Operation | Payload | Successful response |
| --- | --- | --- | --- |
| 01 | WRITE | bank:u8, word_address:u16, word_count:u16, data:4*count bytes | Empty acknowledgment |
| 02 | READ | bank:u8, word_address:u16, word_count:u16 | count packed 32-bit words |
| 03 | START | sequence_length:u16 | Empty acknowledgment |
| 04 | STATUS | Empty | 22 bytes described below |
| 05 | RESET | Empty | Empty acknowledgment |

Bank IDs: Q=0, K=1, V=2, O=3. READ supports all four; WRITE supports Q/K/V only.
Addresses are words, not bytes. Each bank has 1024 words. A packet transfers
1..64 words; address+count must be <=1024. WRITE length must exactly match
the declared count. READ length must be exactly five bytes.

Memory access is rejected while computing (also in the core's one-cycle done
state). START is rejected while an operation is active. Valid sequence lengths
are multiples of eight from 8 to 256. START clears the completion latch and
busy-cycle counter. STATUS remains available while computing. RESET aborts
the computation, preserves SRAM contents, and clears completion/error latches
and the cycle counter. RESET does not reset the UART link. The physical center
button resets both transport/control and compute, also preserving SRAM.

Read all required input data into Q/K/V before START. Firmware does not track
which words have been initialized. The provided high-level client loads and
verifies all three memory images. After reset during compute, O may contain
partial/stale output; only a successful new completion makes it current.

## Status response

| Byte offset | Size | Meaning |
| --- | --- | --- |
| 0 | 2 | ASCII FA |
| 2 | 1 | Protocol version, 1 |
| 3 | 1 | Flags: bit 0 busy, bit 1 done latched, bit 2 error latched |
| 4 | 1 | Operand width, 8 |
| 5 | 1 | Model dimension, 16 |
| 6 | 1 | Batch size, 8 |
| 7 | 1 | Maximum words per packet, 64 |
| 8 | 2 | Words per memory, 1024 |
| 10 | 2 | Maximum tokens, 256 |
| 12 | 4 | Declared clock frequency, 100000000 on board |
| 16 | 4 | Number of cycles with core busy; freezes after completion |
| 20 | 1 | Fractional bits in the compute build, 0 by default |
| 21 | 1 | Q/K layout, 0 = fixed 64-word dimension stride |

Flags and cycle count are captured when STATUS executes. A long response may
arrive after computation has already finished; poll again if the snapshot
still says busy. `busy_cycles/clock_hz` estimates core busy time, excluding UART
transfer time. The counter wraps after 2^32 cycles. Error is diagnostic and
sticky until RESET; an earlier protocol error does not prevent a valid job.

## Response status codes

| Code | Meaning |
| --- | --- |
| 00 | Success |
| 01 | Request CRC mismatch |
| 02 | Unsupported command |
| 03 | Invalid bank, address/count, payload shape, or sequence length |
| 04 | Compute busy; request was not executed |
| 05 | Incomplete frame timed out |
| 06 | UART framing error during a request |
| 07 | Payload length exceeds receiver capacity |

Error responses have no payload. The production inter-byte timeout is 100 ms.
An oversized frame is drained without storing it or executing commands inside
it; after the declared bytes or an inter-byte timeout, BAD_LENGTH is returned.
An isolated first magic byte is silently forgotten after timeout. A partial
header that does not yet include a sequence ID cannot reliably echo the new
request's ID. After a broken request, wait for the timeout before resending.

The client checks response magic, sequence, length and CRC. It does not retry
commands automatically. If an acknowledgment is lost, START may already have
executed. Query STATUS or issue RESET and reload before retrying the whole job.
Use one controlling program per COM port. Pipelining or overlapping requests
is unsupported; the small controller does not queue frames while replying.

## Memory layout

Smallest operand index is the high byte of each word. Q/K word address for
token t, dimension d is `d*64 + t/4`; byte lane is `t%4`. V/O word address is
`t*4 + d/4`; byte lane is `d%4`. Byte value is signed INT8 two's complement.
The Python `pack_matrices` helper performs this conversion and fills unused
input addresses with zero. O contains N*4 meaningful words after completion.

## Scope

UART firmware is a single-bank, sequential load/compute/read design. It has
no DMA, overlap, double buffering, or AXI requirement. Default arithmetic is
still the supplied dummy EXP/RCP. This protocol transports packed data; it
does not implement floating-point quantization or final model precision.
