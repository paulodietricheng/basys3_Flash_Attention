"""PC client for the Basys 3 attention accelerator (Python 3.9+)."""

import argparse
import binascii
import json
from pathlib import Path
import struct
import time


# -----------------------------------------------------------------------------
# Protocol constants and error definitions
# -----------------------------------------------------------------------------

WRITE, READ, START, STATUS, RESET = 1, 2, 3, 4, 5

ERRORS = {
    1: 'bad CRC',
    2: 'unknown command',
    3: 'invalid argument',
    4: 'accelerator busy',
    5: 'incomplete request timeout',
    6: 'UART framing error',
    7: 'request too long',
}


# -----------------------------------------------------------------------------
# Protocol exceptions
# -----------------------------------------------------------------------------

class ProtocolError(RuntimeError):
    pass


class DeviceError(ProtocolError):
    def __init__(self, code):
        self.code = code
        super().__init__(
            f'FPGA error {code}: {ERRORS.get(code, "unknown error")}'
        )


# -----------------------------------------------------------------------------
# Packet helpers
# -----------------------------------------------------------------------------

def crc16(data):
    return binascii.crc_hqx(data, 0xffff)


def request_frame(seq, command, payload=b''):
    if len(payload) > 261:
        raise ValueError('request payload exceeds 261 bytes')

    body = struct.pack('>BBH', seq, command, len(payload)) + payload
    return b'\xa5\x5a' + body + struct.pack('>H', crc16(body))


# -----------------------------------------------------------------------------
# Accelerator transport and command interface
# -----------------------------------------------------------------------------

class Accelerator:
    """Transport must provide read(size) and write(bytes), like serial.Serial.



    Stop-and-wait only. Never automatically retransmit START after a timeout:

    its execution may have succeeded even when an acknowledgment was lost.

    """

    def __init__(self, transport, timeout=3.0):
        self.transport = transport
        self.timeout = timeout
        self.sequence = 0

    def _read_exact(self, n, deadline):
        data = bytearray()

        while len(data) < n:
            if time.monotonic() >= deadline:
                raise TimeoutError(
                    'FPGA response timeout; check bitstream, port, baud and board reset'
                )

            chunk = self.transport.read(n - len(data))
            if chunk:
                data.extend(chunk)

        return bytes(data)

    def transact(self, command, payload=b''):
        seq = self.sequence
        self.sequence = (seq + 1) & 255
        frame = request_frame(seq, command, payload)

        written = self.transport.write(frame)
        if written is not None and written != len(frame):
            raise ProtocolError('partial serial write')

        deadline = time.monotonic() + self.timeout

        while True:
            # Locate response magic; reject corrupted frames instead of retrying actions.
            previous = 0

            while True:
                current = self._read_exact(1, deadline)[0]
                if previous == 0x5a and current == 0xa5:
                    break
                previous = current

            header = self._read_exact(4, deadline)
            response_seq, status, length = struct.unpack('>BBH', header)

            if length > 256:
                raise ProtocolError('invalid response length')

            data = self._read_exact(length, deadline)
            received_crc = struct.unpack(
                '>H', self._read_exact(2, deadline)
            )[0]

            if crc16(header + data) != received_crc:
                raise ProtocolError('response CRC mismatch')

            if response_seq != seq:
                continue

            if status:
                raise DeviceError(status)

            return data

    def status(self):
        p = self.transact(STATUS)

        if len(p) != 22 or p[:3] != b'FA\x01':
            raise ProtocolError('unrecognized firmware/version')

        return dict(
            busy=bool(p[3] & 1),
            done=bool(p[3] & 2),
            error=bool(p[3] & 4),
            operand_bits=p[4],
            d_model=p[5],
            batch_size=p[6],
            max_packet_words=p[7],
            depth=int.from_bytes(p[8:10], 'big'),
            max_tokens=int.from_bytes(p[10:12], 'big'),
            clock_hz=int.from_bytes(p[12:16], 'big'),
            busy_cycles=int.from_bytes(p[16:20], 'big'),
            frac_bits=p[20],
            qk_layout='fixed' if p[21] == 0 else 'dense',
        )

    def reset(self):
        if self.transact(RESET):
            raise ProtocolError('unexpected RESET payload')

    def write_words(self, bank, address, words):
        words = list(words)

        if (
            bank not in (0, 1, 2)
            or not words
            or address < 0
            or address + len(words) > 1024
        ):
            raise ValueError(
                'write requires Q/K/V bank and a nonempty in-range word span'
            )

        for offset in range(0, len(words), 64):
            block = words[offset:offset + 64]
            data = (
                struct.pack('>BHH', bank, address + offset, len(block))
                + struct.pack('>' + 'I' * len(block), *block)
            )

            if self.transact(WRITE, data):
                raise ProtocolError('unexpected WRITE payload')

    def read_words(self, bank, address, count):
        if (
            bank not in (0, 1, 2, 3)
            or count <= 0
            or address < 0
            or address + count > 1024
        ):
            raise ValueError(
                'read requires a valid bank and a nonempty in-range word span'
            )

        words = []

        for offset in range(0, count, 64):
            size = min(64, count - offset)
            p = self.transact(
                READ,
                struct.pack('>BHH', bank, address + offset, size),
            )

            if len(p) != 4 * size:
                raise ProtocolError('incorrect READ response length')

            words.extend(struct.unpack('>' + 'I' * size, p))

        return words

    def start(self, n):
        if n < 8 or n > 256 or n % 8:
            raise ValueError('sequence length must be 8,16,...,256')

        if self.transact(START, struct.pack('>H', n)):
            raise ProtocolError('unexpected START payload')

    def wait_done(self, timeout=10.0, poll_interval=0.01):
        deadline = time.monotonic() + timeout

        while time.monotonic() < deadline:
            status = self.status()

            if status['done'] and not status['busy']:
                return status

            time.sleep(poll_interval)

        raise TimeoutError(
            'compute timeout; STATUS or RESET can be used to recover'
        )

    def load_images(self, images, verify=True):
        status = self.status()

        if (
            status['operand_bits'],
            status['d_model'],
            status['depth'],
            status['qk_layout'],
        ) != (8, 16, 1024, 'fixed'):
            raise ProtocolError('client layout does not match this firmware')

        if len(images) != 3 or any(len(image) != 1024 for image in images):
            raise ValueError(
                'three complete 1024-word memory images are required'
            )

        for bank, image in enumerate(images):
            self.write_words(bank, 0, image)

            if verify and self.read_words(bank, 0, len(image)) != image:
                raise ProtocolError(
                    f'input memory verification failed for bank {bank}'
                )

    def run_fixture(
        self,
        folder,
        verify=True,
        poll_interval=0.01,
        reset_before=True,
    ):
        folder = Path(folder)
        n = int((folder / 'n.txt').read_text())

        if reset_before:
            self.reset()

        self.load_images(
            [read_hex(folder / f'{name}.hex') for name in ('q', 'k', 'v')],
            verify,
        )
        self.start(n)

        status = self.wait_done(poll_interval=poll_interval)
        words = self.read_words(3, 0, n * 4)
        expected = read_hex(folder / 'out.hex')

        if words != expected:
            mismatch = next(
                (
                    i
                    for i, (a, b) in enumerate(zip(words, expected))
                    if a != b
                ),
                None,
            )
            raise ProtocolError(
                f'output differs from fixture at word {mismatch}; check arithmetic mode'
            )

        return status, unpack_output(words, n)


# -----------------------------------------------------------------------------
# Data packing / unpacking helpers
# -----------------------------------------------------------------------------

def read_hex(path):
    return [int(line, 16) for line in Path(path).read_text().split()]


def pack_matrices(q, k, v):
    n = len(q)

    if n < 8 or n > 256 or n % 8:
        raise ValueError('N must be 8,16,...,256')

    for matrix in (q, k, v):
        if len(matrix) != n or any(len(row) != 16 for row in matrix):
            raise ValueError('Q/K/V must each be N x 16')

        if any(
            type(x) is not int or not -128 <= x <= 127
            for row in matrix
            for x in row
        ):
            raise ValueError('matrix values must be signed INT8 integers')

    images = []

    for matrix in (q, k):
        image = [0] * 1024

        for r, row in enumerate(matrix):
            for d, value in enumerate(row):
                image[d * 64 + r // 4] |= (
                    (value & 255) << (24 - 8 * (r % 4))
                )

        images.append(image)

    data = bytes(value & 255 for row in v for value in row)
    data += bytes(4096 - len(data))
    images.append(list(struct.unpack('>1024I', data)))

    return images


def unpack_output(words, n):
    data = struct.pack('>' + 'I' * len(words), *words)
    signed = [x if x < 128 else x - 256 for x in data]
    return [signed[r * 16:(r + 1) * 16] for r in range(n)]


# -----------------------------------------------------------------------------
# Command-line interface
# -----------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', help='Windows COM port, e.g. COM5')
    parser.add_argument('--baud', type=int, default=115200)

    sub = parser.add_subparsers(dest='action', required=True)
    sub.add_parser('ports')
    sub.add_parser('status')
    sub.add_parser('reset')
    sub.add_parser('smoke')

    fixture = sub.add_parser('run-fixture')
    fixture.add_argument('folder', type=Path)

    matrices = sub.add_parser('run-matrices')
    matrices.add_argument('input', type=Path)
    matrices.add_argument('--output', type=Path, required=True)

    args = parser.parse_args()

    try:
        import serial

        if args.action == 'ports':
            from serial.tools import list_ports

            for port in list_ports.comports():
                print(f'{port.device}: {port.description}')
            return

        if not args.port:
            parser.error('--port is required for this action')

        with serial.Serial(
            args.port,
            args.baud,
            bytesize=8,
            parity='N',
            stopbits=1,
            timeout=0.1,
            write_timeout=3,
            xonxoff=False,
            rtscts=False,
            dsrdtr=False,
        ) as link:
            link.reset_input_buffer()
            device = Accelerator(link)

            if args.action == 'status':
                print(json.dumps(device.status(), indent=2))

            elif args.action == 'reset':
                device.reset()
                print('Compute reset; SRAM contents preserved.')

            elif args.action == 'smoke':
                if device.status()['busy']:
                    raise ProtocolError(
                        'wait for compute to finish before smoke test'
                    )

                original = device.read_words(0, 0, 4)

                try:
                    pattern = [
                        0x12345678,
                        0xFEDCBA98,
                        0xA55A00FF,
                        0x80017F00,
                    ]
                    device.write_words(0, 0, pattern)

                    if device.read_words(0, 0, 4) != pattern:
                        raise ProtocolError('BRAM smoke readback failed')

                finally:
                    device.write_words(0, 0, original)

                print(
                    'PASS UART and Q BRAM write/readback; original words restored.'
                )

            elif args.action == 'run-fixture':
                status, _ = device.run_fixture(args.folder)
                print('PASS input readback and exact O comparison.')
                print(json.dumps(status, indent=2))

            else:
                data = json.loads(args.input.read_text())
                q, k, v = (data[key] for key in ('Q', 'K', 'V'))
                images = pack_matrices(q, k, v)

                device.reset()
                device.load_images(images)
                device.start(len(q))

                status = device.wait_done()
                output = unpack_output(
                    device.read_words(3, 0, len(q) * 4),
                    len(q),
                )

                args.output.write_text(
                    json.dumps({'O': output, 'status': status}, indent=2) + '\n'
                )
                print(
                    f'Wrote {args.output}; default firmware uses dummy EXP/RCP.'
                )

    except ImportError:
        parser.exit(
            1,
            'Install dependencies: python -m pip install -r host/requirements.txt\n',
        )

    except (ProtocolError, TimeoutError, ValueError, OSError, KeyError) as exc:
        parser.exit(1, f'Error: {exc}\n')


if __name__ == '__main__':
    main()
