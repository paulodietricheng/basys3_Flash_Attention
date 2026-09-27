from pathlib import Path
import json, os, shutil, subprocess, sys
from generate_cases import generate

ROOT=Path(__file__).resolve().parents[1]
env=os.environ.copy()
env['PYTHONPATH']=str(ROOT.parent/'check_deps')+os.pathsep+env.get('PYTHONPATH','')
VERILATOR=[shutil.which('verilator')] if shutil.which('verilator') else [sys.executable,'-m','verilator']
RTL=['fa_pkg','bram','sram','attention_ctrl','rd_addr_gen','sram_ctrl','o_writer','vpu_v_fetch','scl','vpu_row','vpu','fa_top']

def run_bram():
    generate(False,False)
    build=ROOT/'build'/'bram'
    build.mkdir(parents=True,exist_ok=True)
    (ROOT/'results').mkdir(exist_ok=True)
    args=VERILATOR+['--binary','--timing','--assert','--top-module','tb_bram',
                    '--Mdir',str(build),'-j','2',str(ROOT/'rtl/bram.sv'),str(ROOT/'tests/tb_bram.sv')]
    p=subprocess.run(args,capture_output=True,text=True,env=env)
    (ROOT/'results'/'bram_build.log').write_text(p.stdout+p.stderr)
    if p.returncode: print(p.stdout+p.stderr);raise RuntimeError('BRAM build failed')
    p=subprocess.run([str(build/'Vtb_bram')],cwd=ROOT,capture_output=True,text=True,env=env,timeout=30)
    (ROOT/'results'/'bram.log').write_text(p.stdout+p.stderr)
    print(p.stdout+p.stderr,flush=True)
    if p.returncode: raise RuntimeError('BRAM test failed')

def run(reference,dense):
    name=('reference' if reference else 'dummy')+('_dense' if dense else '_fixed')
    fixtures,cases=generate(reference,dense)
    build=ROOT/'build'/name
    build.mkdir(parents=True,exist_ok=True)
    (ROOT/'results').mkdir(exist_ok=True)
    files=[ROOT/'rtl'/f'{f}.sv' for f in RTL]
    files+=([ROOT/'tests/reference_math.sv'] if reference else [ROOT/'rtl/exp.sv',ROOT/'rtl/rcp.sv'])
    # Use Paulo's actual control, handler, skewer, array and PE RTL.
    files += [ROOT/'rtl'/f'{f}.sv' for f in ['mxu','mxu_ctrl','mxu_op_handler','mxu_op_skewer','mxu_systolic_array','pe']]
    files += [ROOT/'tests/tb_compute.sv']
    args=VERILATOR+['--binary','--timing','--assert','--output-split','0','--output-split-cfuncs','0',
                    '-Wno-fatal','--top-module','tb_compute',f'-GDENSE={int(dense)}',
                    '--Mdir',str(build),'-j','2']
    if reference: args+=['+define+FA_REFERENCE_Q16']
    p=subprocess.run(args+[str(f) for f in files],capture_output=True,text=True,env=env)
    (ROOT/'results'/f'{name}_build.log').write_text(p.stdout+p.stderr)
    if p.returncode: print((p.stdout+p.stderr)[-6000:]);raise RuntimeError(name+' build failed')
    p=subprocess.run([str(build/'Vtb_compute'),f'+ROOT={fixtures}',f'+JOBS={len(cases)}'],
                     capture_output=True,text=True,env=env,timeout=600)
    (ROOT/'results'/f'{name}.log').write_text(p.stdout+p.stderr)
    print(name,p.stdout[-2200:],p.stderr,flush=True)
    if p.returncode: raise RuntimeError(name+' scoreboard failed')
    return {'mode':name,'jobs':len(cases),'restart_jobs':3,'max_float_error':max(c['max_float_error'] for c in cases),
            'commands':sum((c['n']//8)**2 for c in cases)+3,
            'output_words':sum(c['n']*4 for c in cases)+3*32,'passed':True}

if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='bram':
        run_bram()
        sys.exit(0)
    modes=[(False,False),(False,True),(True,False),(True,True)]
    if len(sys.argv)>1: modes=[m for m in modes if ('reference' if m[0] else 'dummy')+('_dense' if m[1] else '_fixed') in sys.argv[1:]]
    if len(sys.argv)==1: run_bram()
    results=[run(*mode) for mode in modes]
    (ROOT/'results'/('summary_'+'_'.join(r['mode'] for r in results)+'.json')).write_text(json.dumps(results,indent=2))
