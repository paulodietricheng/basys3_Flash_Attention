"""Run every regression in this package, failing on the first error."""
from pathlib import Path
import subprocess,sys
ROOT=Path(__file__).resolve().parent
for script,args in [('run.py',[]),('test_serial.py',[]),('test_serial.py',['--production-baud']),('run_uart_sv.py',[])]:
    subprocess.run([sys.executable,str(ROOT/script),*args],check=True)
print('PASS all core, BRAM, UART, client and standalone serial-testbench regressions')
