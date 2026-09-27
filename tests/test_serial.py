"""Run the real Python PC client against bit-level UART + accelerator RTL."""
from pathlib import Path
import json, os, shutil, struct, subprocess, sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'host'))
from fa_client import Accelerator, DeviceError, crc16, request_frame, WRITE, READ, START, STATUS
from fa_client import pack_matrices, unpack_output
from generate_cases import generate, score, compute

class SimTransport:
    def __init__(self, executable):
        self.proc=subprocess.Popen([str(executable)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,
                                   stderr=None,text=True,bufsize=1)
        self.buffer=bytearray()
    def exchange(self, data, op='X'):
        self.proc.stdin.write(f'{op} {data.hex()}\n');self.proc.stdin.flush()
        line=self.proc.stdout.readline().strip()
        if not line: raise RuntimeError('RTL simulator exited')
        if line=='-': return b''
        try: return bytes.fromhex(line)
        except ValueError as exc: raise RuntimeError(f'Unexpected simulator output: {line}') from exc
    def write(self,data):
        self.buffer.extend(self.exchange(data));return len(data)
    def read(self,count):
        result=bytes(self.buffer[:count]);del self.buffer[:count];return result
    def close(self):
        if self.proc.poll() is None:
            self.proc.stdin.write('Q\n');self.proc.stdin.flush()
        self.proc.wait(timeout=5)
        if self.proc.returncode: raise RuntimeError('RTL simulation failed')

def build(production=False):
    name='uart_production_baud' if production else 'uart_serial'
    target=ROOT/'build'/name;target.mkdir(parents=True,exist_ok=True)
    (ROOT/'results').mkdir(exist_ok=True)
    env=os.environ.copy()
    env['PYTHONPATH']=str(ROOT.parent/'check_deps')+os.pathsep+env.get('PYTHONPATH','')
    compiler=[shutil.which('verilator')] if shutil.which('verilator') else [sys.executable,'-m','verilator']
    files=[str(ROOT/line.strip()) for line in (ROOT/'rtl/files.f').read_text().splitlines() if line.strip()]
    args=compiler+['--cc','--exe','--build','--assert','--timing','-Wno-fatal','--output-split','0',
                   '--output-split-cfuncs','0','--top-module','fa_uart_top','--Mdir',str(target),'-j','2']
    if production: args+=['-CFLAGS','-DUART_CPB=868']
    else: args+=['-GCLK_HZ=800000','-GBAUD=100000','-GRX_TIMEOUT_CYCLES=4096']
    p=subprocess.run(args+files+[str(ROOT/'tests/uart_bridge.cpp')],env=env,capture_output=True,text=True)
    (ROOT/'results'/f'{name}_build.log').write_text(p.stdout+p.stderr)
    if p.returncode: print((p.stdout+p.stderr)[-6000:]);raise RuntimeError('serial RTL build failed')
    return target/'Vfa_uart_top'

def error(device,command,payload,code):
    try: device.transact(command,payload)
    except DeviceError as exc: assert exc.code==code,(exc.code,code)
    else: raise AssertionError('invalid request was accepted')

def check_raw(reply,seq,status):
    assert reply[:2]==b'\x5a\xa5' and reply[2]==seq and reply[3]==status,reply.hex()
    assert len(reply)==8+int.from_bytes(reply[4:6],'big')
    assert crc16(reply[2:-2])==int.from_bytes(reply[-2:],'big')

def run(production=False):
    fixtures,_=generate(False,False)
    transport=SimTransport(build(production))
    device=Accelerator(transport,timeout=1)
    checks=[]
    def passed(message): checks.append(message);print('PASS',message,flush=True)
    try:
        assert crc16(b'123456789')==0x29b1
        info=device.status()
        assert not info['busy'] and not info['done'] and not info['error']
        assert info['clock_hz']==(100000000 if production else 800000)
        passed('capabilities, startup and CRC standard vector')
        pattern=[0x12345678,0xFEDCBA98,0xA55A00FF,0x80017F00]
        device.write_words(0,0,pattern)
        assert device.read_words(0,0,4)==pattern
        passed('real Python client writes and reads actual Q BRAM over serial pins')
        if production:
            # Approximately +/-1% host baud mismatch, with independent stimulus timing.
            for clocks in (860,876):
                reply=transport.exchange(request_frame(99,STATUS),op=f'P {clocks}')
                check_raw(reply,99,0)
            passed('100 MHz / 115200 baud plus approximately +/-1% peer baud variation')
        else:
            for bank in (0,1,2):
                device.write_words(bank,1023,[0x8000FF7F+bank])
                assert device.read_words(bank,1023,1)==[0x8000FF7F+bank]
            many=[(i*0x1020304)&0xffffffff for i in range(65)]
            device.write_words(1,70,many);assert device.read_words(1,70,65)==many
            passed('all input banks, maximum address, and 64-word packet chunk boundary')

            bad=bytearray(request_frame(51,WRITE,struct.pack('>BHHI',0,0,1,0xDEADBEEF)))
            bad[-1]^=1
            check_raw(transport.exchange(bad),51,1)
            assert device.read_words(0,0,4)==pattern
            passed('CRC failure rejects entire write before memory changes')
            error(device,0x99,b'',2)
            for bank,address,count in ((4,0,1),(0,1024,1),(0,1023,2),(0,0,0),(0,0,65)):
                error(device,READ,struct.pack('>BHH',bank,address,count),3)
            error(device,WRITE,struct.pack('>BHHI',3,0,1,0),3)
            error(device,WRITE,struct.pack('>BHH',0,0,1),3)
            for n in (0,7,9,257,264): error(device,START,struct.pack('>H',n),3)
            passed('invalid opcode, bank, range, write-to-O, length, and sequence length')

            body=struct.pack('>BBH',52,WRITE,262)+bytes(262)
            check_raw(transport.exchange(b'\xa5\x5a'+body+struct.pack('>H',crc16(body))),52,7)
            check_raw(transport.exchange(b'\xa5\x5a'+struct.pack('>BBH',53,WRITE,65535)),53,7)
            check_raw(transport.exchange(request_frame(54,WRITE,struct.pack('>BHHI',0,0,1,1))[:-3]),54,5)
            check_raw(transport.exchange(request_frame(55,STATUS),op='F'),55,6)
            check_raw(transport.exchange(b'\x00\xff\xa5'+request_frame(56,STATUS)),56,0)
            assert transport.exchange(b'\xa5')==b''
            assert device.status()['error']
            passed('oversize drain, truncated frame timeout, framing error and stream resynchronization')
            device.sequence=254
            for _ in range(4): device.status()
            assert device.sequence==2
            passed('sequence ID wraps through 255 to zero')

            device.start(256)
            assert device.status()['busy']
            error(device,WRITE,struct.pack('>BHHI',0,0,1,0),4)
            error(device,READ,struct.pack('>BHH',0,0,1),4)
            error(device,START,struct.pack('>H',8),4)
            device.reset()
            info=device.status()
            assert not info['busy'] and not info['done'] and not info['error']
            assert device.read_words(0,0,4)==pattern
            passed('busy protection and serial reset abort with SRAM retention')

            for case in (0,1,31,0):
                status,result=device.run_fixture(fixtures/f'{case:03d}',poll_interval=0,reset_before=False)
                assert status['done'] and not status['busy'] and status['busy_cycles']>0
                assert device.status()['done'] # sticky completion survives polling
                passed(f'end-to-end UART load/readback/compute/O compare: N={len(result)}')

            q=[[d-8 for d in range(16)] for _ in range(8)]
            k=[[r%3-1 for _ in range(16)] for r in range(8)]
            v=[[r-d for d in range(16)] for r in range(8)]
            images=pack_matrices(q,k,v)
            assert images[0][0]==0xf8f8f8f8 and images[2][0]==0x00fffefd
            device.load_images(images);device.start(8);device.wait_done(poll_interval=0)
            actual=device.read_words(3,0,32)
            expected,_,_=compute(score(q,k),v,False)
            assert actual==expected and len(unpack_output(actual,8))==8
            passed('Python N x 16 matrix packing, signed bytes and software-reference output')
    finally: transport.close()
    name='uart_production_baud' if production else 'uart_serial'
    (ROOT/'results'/f'{name}.json').write_text(json.dumps({'passed':True,'checks':checks},indent=2)+'\n')

if __name__=='__main__': run('--production-baud' in sys.argv)
