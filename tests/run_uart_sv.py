"""Compile/run the same standalone serial testbench selected by Vivado."""
from pathlib import Path
import os, shutil, subprocess, sys
from generate_cases import generate

ROOT=Path(__file__).resolve().parents[1]
case=int(sys.argv[1]) if len(sys.argv)>1 else 0
fixtures,_=generate(False,False)
env=os.environ.copy()
env['PYTHONPATH']=str(ROOT.parent/'check_deps')+os.pathsep+env.get('PYTHONPATH','')
compiler=[shutil.which('verilator')] if shutil.which('verilator') else [sys.executable,'-m','verilator']
build=ROOT/'build'/'tb_uart';build.mkdir(parents=True,exist_ok=True)
(ROOT/'results').mkdir(exist_ok=True)
files=[str(ROOT/line.strip()) for line in (ROOT/'rtl/files.f').read_text().splitlines() if line.strip()]
args=compiler+['--binary','--timing','--assert','-Wno-fatal','--output-split','0','--output-split-cfuncs','0',
              '--top-module','tb_uart','--Mdir',str(build),'-j','2']
p=subprocess.run(args+files+[str(ROOT/'tests/tb_uart.sv')],env=env,capture_output=True,text=True)
(ROOT/'results'/'tb_uart_build.log').write_text(p.stdout+p.stderr)
if p.returncode: print((p.stdout+p.stderr)[-6000:]);raise RuntimeError('tb_uart build failed')
p=subprocess.run([str(build/'Vtb_uart'),f'+ROOT={fixtures}',f'+CASE={case}'],env=env,
                 capture_output=True,text=True,timeout=300)
(ROOT/'results'/f'tb_uart_case_{case}.log').write_text(p.stdout+p.stderr)
print(p.stdout+p.stderr)
if p.returncode: raise RuntimeError('tb_uart failed')
