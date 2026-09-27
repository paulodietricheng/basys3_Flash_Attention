"""Independent bit-accurate placeholder/Q16 models and dense float attention."""
from pathlib import Path
import json, math, random

ROOT=Path(__file__).resolve().parents[1]
def s32(x):
    x &= 0xffffffff
    return x if x < 0x80000000 else x-0x100000000
def pack(values):
    out=[]
    for i in range(0,len(values),4):
        out.append(sum((values[i+j]&255)<<(24-8*j) for j in range(4)))
    return out
def write_hex(path,values):
    path.write_text(''.join(f'{v&0xffffffff:08x}\n' for v in values))
def score(q,k):
    return [[sum(a*b for a,b in zip(qrow,krow)) for krow in k] for qrow in q]
def compute(scores,v,reference):
    frac=16 if reference else 0
    scale=1<<frac
    def mul(a,b): return s32((a*b)>>frac)
    def exp(x): return int(math.floor(math.exp(x/4)*scale+0.5)) if reference else s32(x+1)
    out=[]; norm=[]; max_error=0.0
    for row in scores:
        m=-2147483648; d=0; u=[0]*16
        for x,vec in zip(row,v):
            mn=max(m,x)
            rho=0 if d==0 else exp(s32(m-mn))
            beta=exp(s32(x-mn))
            u=[s32(mul(a,rho)+mul(b*scale,beta)) for a,b in zip(u,vec)]
            d=s32(mul(d,rho)+beta); m=mn
        inv=int(math.floor(scale*scale/d+0.5)) if reference else s32(d-2)
        result=[mul(a,inv) for a in u]
        norm.extend(result)
        out.extend((a>>frac)&255 for a in result)
        if reference:
            weights=[math.exp((x-max(row))/4) for x in row]
            denom=sum(weights)
            gold=[sum(w*vec[j] for w,vec in zip(weights,v))/denom for j in range(16)]
            error=max(abs(a/scale-b) for a,b in zip(result,gold))
            max_error=max(max_error,error)
    return pack(out),norm,max_error

def generate(reference=False,dense=False):
    mode=('reference' if reference else 'dummy')+('_dense' if dense else '_fixed')
    dest=ROOT/'fixtures'/mode;dest.mkdir(parents=True,exist_ok=True)
    cases=[]
    # All supported sizes, followed by consecutive short jobs with distinct data.
    sizes=list(range(8,257,8))+[16,24,16,8,8]
    for case,n in enumerate(sizes):
        rng=random.Random(39001+case)
        q=[[rng.randrange(-2,3) for _ in range(16)] for _ in range(n)]
        k=[[rng.randrange(-2,3) for _ in range(16)] for _ in range(n)]
        v=[[rng.randrange(-31,32) for _ in range(16)] for _ in range(n)]
        if case==35: q=[[0]*16 for _ in range(n)];v=[[7]*16 for _ in range(n)]
        if case==36:
            q=[[1]+[0]*15 for _ in range(n)]
            k=[[j-4]+[0]*15 for j in range(n)]
            v=[[j-d for d in range(16)] for j in range(n)]
        scores=score(q,k)
        words,norm,error=compute(scores,v,reference)
        if reference: assert error<0.005,(n,error)
        stride=n//4 if dense else 64
        memories=[]
        for mat in (q,k):
            mem=[0]*1024
            for d in range(16):
                packed=pack([mat[r][d] for r in range(n)])
                mem[d*stride:d*stride+len(packed)]=packed
            memories.append(mem)
        memories.append(pack([x for row in v for x in row])+[0]*(1024-n*4))
        folder=dest/f'{case:03d}';folder.mkdir(exist_ok=True)
        for name,mem in zip(('q','k','v'),memories): write_hex(folder/f'{name}.hex',mem)
        write_hex(folder/'scores.hex',[x for row in scores for x in row])
        write_hex(folder/'out.hex',words)
        write_hex(folder/'norm.hex',norm)
        (folder/'n.txt').write_text(str(n)+'\n')
        cases.append({'n':n,'max_float_error':error})
    (dest/'manifest.json').write_text(json.dumps(cases,indent=2))
    return dest,cases

if __name__=='__main__':
    for ref in (False,True):
        for dense in (False,True):
            path,cases=generate(ref,dense)
            print(path.name,len(cases),'max_float_error',max(c['max_float_error'] for c in cases))
