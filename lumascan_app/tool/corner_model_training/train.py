"""Fine-tunes the DocAligner corner model on the app's marked photos.

Usage: python3 train.py ALL STEPS OUT.pt
  ALL 0 keeps every 4th photo back to score on; 1 trains on all of them.
Start from base.pt (see README.md). CPU only is fine: about 1.6 s a step.

Set MAPS=corners to train the four corner heatmaps alone, as the first
LumaScan model (v1) was. By default the model also learns two maps of the
page itself (docs/edge-model.md, phase 2): its area and its outline.
For a photo with more than one marked outline (an open book: either page,
or the spread) the corner maps then show the corners of each (PLACES=every;
PLACES=first trains on the first outline alone, as v1 did), and the area
and outline maps show the first, the page meant.
SEED fixes the random samples, so two runs can be compared.
"""
import os,sys,time,random,torch,cv2,numpy as np
from data import *
torch.set_num_threads(4)
CARDS=os.environ.get('CARDS','/mnt/project-files/id_mask_test')  # made ID card photos, optional
ALL=int(sys.argv[1]); STEPS=int(sys.argv[2]); OUT=sys.argv[3]
EXTRA=os.environ.get('MAPS','corners+page')!='corners'   # also learn the page's area and outline
EVERY=os.environ.get('PLACES','every' if EXTRA else 'first')=='every'   # corner maps show every marked outline's corners
if 'SEED' in os.environ: random.seed(int(os.environ['SEED'])); np.random.seed(int(os.environ['SEED'])); torch.manual_seed(int(os.environ['SEED']))
S=all_samples()
def load(f):
    im=cv2.cvtColor(cv2.imread(f),cv2.COLOR_BGR2RGB); h,w=im.shape[:2]; s=720/max(h,w)
    return cv2.resize(im,(round(w*s),round(h*s)),interpolation=cv2.INTER_AREA)
data=[(load(f),qs[0],g) for i,(f,qs,g) in enumerate(S) if ALL or not is_val(i)]
others=[qs[1:] for i,(f,qs,g) in enumerate(S) if ALL or not is_val(i)]   # the other outlines that count as the page, same order as data
val=[(load(f),qs,g) for i,(f,qs,g) in enumerate(S) if is_val(i)]
print(len(data),len(val),flush=True)
N=256;H=128;SIG=2.8
yy,xx=np.mgrid[0:H,0:H]
def canon(p):
    c=p.mean(0);p=p[np.argsort(np.arctan2(p[:,1]-c[1],p[:,0]-c[0]))];return np.roll(p,-np.argmin(p.sum(1)),0)
def sample_real():
    k=random.randrange(len(data)); im,q,g=data[k]; h,w=im.shape[:2]
    # source frame in normalised coords -> output 0..1 with random perspective/zoom/rotation
    s=random.uniform(0.75,1.25) if random.random()<0.7 else 1.0
    ang=np.deg2rad(random.uniform(-12,12)) if random.random()<0.6 else 0
    src=np.array([[0,0],[1,0],[1,1],[0,1]],np.float32)
    c=np.array([0.5+random.uniform(-.08,.08),0.5+random.uniform(-.08,.08)])
    R_=np.array([[np.cos(ang),-np.sin(ang)],[np.sin(ang),np.cos(ang)]])
    dst=((src-0.5)@R_.T)*s+c + np.random.uniform(-.06,.06,(4,2)) if random.random()<0.85 else src.copy()
    if random.random()<0.5: dst[:,0]=1-dst[:,0]; flip=True
    M=cv2.getPerspectiveTransform(src.astype(np.float32),dst.astype(np.float32))
    Spx=np.diag([1/w,1/h,1]); Dpx=np.diag([N,N,1])
    Mp=Dpx@M@Spx
    bg=random.choice(data)[0]; bg=cv2.resize(bg,(N,N)); 
    if random.random()<0.5: bg=cv2.GaussianBlur(bg,(0,0),random.uniform(1,6))
    out=cv2.warpPerspective(im,Mp,(N,N),flags=cv2.INTER_LINEAR,borderMode=cv2.BORDER_CONSTANT,borderValue=0)
    mask=cv2.warpPerspective(np.ones((h,w),np.uint8),Mp,(N,N),flags=cv2.INTER_NEAREST)
    if random.random()<0.5: out=np.where(mask[...,None]>0,out,bg)
    else: out=np.where(mask[...,None]>0,out,cv2.warpPerspective(im,Mp,(N,N),borderMode=cv2.BORDER_REFLECT))
    p=canon(cv2.perspectiveTransform(q.reshape(1,4,2).astype(np.float32),M)[0])
    more=[canon(cv2.perspectiveTransform(o.reshape(1,4,2).astype(np.float32),M)[0]) for o in others[k]] if EVERY else []
    return finish(out),targets(p,more)

def rand_bg():
    r=random.random()
    if r<0.6:
        k=random.randrange(len(data)); im,q,g=data[k]; h,w=im.shape[:2]
        m=np.zeros((h,w),np.uint8)
        for o in [q]+(others[k] if EVERY else []): cv2.fillPoly(m,[np.round(o*[w-1,h-1]).astype(np.int32)],1)
        for _ in range(20):
            cw=random.randint(w//5,w//2); ch=random.randint(h//6,h//2); x=random.randint(0,w-cw); y=random.randint(0,h-ch)
            if m[y:y+ch,x:x+cw].mean()<0.02: return cv2.resize(im[y:y+ch,x:x+cw],(N,N))
    if r<0.9:
        c1=np.random.randint(0,255,3); c2=np.clip(c1+np.random.randint(-60,60,3),0,255)
        t=np.linspace(0,1,N)[:,None,None] if random.random()<0.5 else np.linspace(0,1,N)[None,:,None]
        b=(c1*(1-t)+c2*t)*np.ones((N,N,1)); b=b+np.random.normal(0,random.uniform(1,15),(N,N,3))
        if random.random()<0.5: b=cv2.GaussianBlur(b.astype(np.float32),(0,0),random.uniform(1,4))
        return np.clip(b,0,255).astype(np.uint8)
    b=np.random.randint(0,255,(N//8,N//8,3)).astype(np.uint8); return cv2.resize(b,(N,N),interpolation=random.choice([cv2.INTER_LINEAR,cv2.INTER_CUBIC]))
def rect_page():
    if random.random()<0.4:
        # a made card: coloured header band, light body, text-like lines
        w,h=428,270; c=np.full((h,w,3),random.randint(225,252),np.uint8); c[...,random.randint(0,2)]-=random.randint(0,15)
        band=random.randint(0,60); 
        if band>8: c[:band]=np.random.randint(0,200,3)
        for _ in range(random.randint(3,9)):
            y=random.randint(band+10,h-15); x=random.randint(10,w//2); cv2.line(c,(x,y),(min(w-10,x+random.randint(40,250)),y),(random.randint(0,90),)*3,random.randint(2,6))
        if random.random()<0.6: cv2.rectangle(c,(15,band+15),(80,band+95),(120,120,120),1)
        return c
    im,q,g=random.choice(data); h,w=im.shape[:2]; p=(q*[w,h]).astype(np.float32)
    W=int(max(np.linalg.norm(p[1]-p[0]),np.linalg.norm(p[2]-p[3]))); Hh=int(max(np.linalg.norm(p[3]-p[0]),np.linalg.norm(p[2]-p[1])))
    M=cv2.getPerspectiveTransform(p,np.float32([[0,0],[W,0],[W,Hh],[0,Hh]]))
    return cv2.warpPerspective(im,M,(W,Hh))
def synth():
    pg=rect_page(); h,w=pg.shape[:2]; bg=rand_bg().copy()
    s=random.uniform(0.35,0.85); ar=w/h
    if ar>1: dw,dh=s,s/ar*random.uniform(.8,1.2)
    else: dh,dw=s,s*ar*random.uniform(.8,1.2)
    cx,cy=random.uniform(dw/2,1-dw/2),random.uniform(dh/2,1-dh/2); ang=np.deg2rad(random.uniform(-25,25))
    base=np.array([[-dw/2,-dh/2],[dw/2,-dh/2],[dw/2,dh/2],[-dw/2,dh/2]])
    Rm=np.array([[np.cos(ang),-np.sin(ang)],[np.sin(ang),np.cos(ang)]])
    d=base@Rm.T+[cx,cy]+np.random.uniform(-.04,.04,(4,2)); d=np.clip(d,0.02,0.98)
    M=cv2.getPerspectiveTransform(np.float32([[0,0],[w,0],[w,h],[0,h]]),np.float32(d*N))
    o=cv2.warpPerspective(pg,M,(N,N)); m=cv2.warpPerspective(np.full((h,w),255,np.uint8),M,(N,N))
    if random.random()<0.5: # soft shadow
        sh=cv2.GaussianBlur(cv2.warpAffine(m,np.float32([[1,0,random.randint(2,8)],[0,1,random.randint(2,8)]]),(N,N)),(0,0),4)/255
        bg=(bg*(1-0.4*sh[...,None])).astype(np.uint8)
    out=np.where(m[...,None]>127,o,bg)
    return out,canon(d)
def heat(p): return np.stack([np.exp(-((xx-x*(H-1))**2+(yy-y*(H-1))**2)/(2*SIG*SIG)) for x,y in np.clip(p,0,1)]).astype(np.float32)
CH=6 if EXTRA else 4
def targets(p,more=()):
    """What the model should answer for a page with corners p (TL, TR, BR, BL, 0..1; a corner may
    lie off the frame): a peak at each corner (put on the frame edge when off it), then the page's
    area filled in, then its outline as a soft line about 3 cells wide. `more` are other outlines
    that would count as the page too (the other page of an open book, the whole spread): their
    corners get peaks as well, so every place a corner may be shows, while the area and the
    outline stay those of p, the page meant."""
    if p is None: return np.zeros((CH,H,H),np.float32)
    t=heat(p)
    for o in more: t=np.maximum(t,heat(o))
    if not EXTRA: return t
    px=np.round(p*(H-1)*16).astype(np.int32)   # 4 fractional bits
    area=np.zeros((H,H),np.uint8); cv2.fillPoly(area,[px],255,lineType=cv2.LINE_AA,shift=4)
    edge=np.zeros((H,H),np.uint8); cv2.polylines(edge,[px],True,255,1,lineType=cv2.LINE_AA,shift=4)
    edge=cv2.GaussianBlur(edge.astype(np.float32)/255,(0,0),1.0); edge=np.minimum(1,edge/0.4)
    return np.concatenate([t,area[None].astype(np.float32)/255,edge[None]]).astype(np.float32)
def finish(o):
    o=o.astype(np.float32)
    if random.random()<0.8:
        o=o*random.uniform(.6,1.3)+random.uniform(-30,30); o=o*np.random.uniform(.85,1.15,3)
        if random.random()<0.2: o=np.repeat(o.mean(2,keepdims=True),3,2)
    if random.random()<0.3: o=cv2.GaussianBlur(o,(0,0),random.uniform(.5,1.8))
    if random.random()<0.3: o=o+np.random.normal(0,random.uniform(2,10),o.shape)
    return (np.clip(o,0,255)/255).transpose(2,0,1).astype(np.float32)
def sample():
    r=random.random()
    if r<0.12: return finish(rand_bg()),targets(None)
    if r<0.35:
        o,p=synth(); return finish(o),targets(p)
    return sample_real()
def evaluate(net):
    net.eval(); r=[]; areas=[]
    with torch.no_grad():
        for im,qs,g in val:
            h=net(torch.from_numpy(prep(im))[None])[0].numpy(); q,c=read_heat(h)
            r.append((0 if q is None else max(quad_iou(q,t) for t in qs),c,g))
            if EXTRA: areas.append(max(mask_iou(h[4],t) for t in qs))
    random.seed(7); negs=[rand_bg() for _ in range(20)]; random.seed()
    with torch.no_grad():
        neg=net(torch.from_numpy(np.stack([prep(n) for n in negs])))
        negpk=neg.flatten(2).max(2).values.min(1).values.numpy()
        cq=np.array([[.138,.18],[.862,.18],[.862,.817],[.138,.817]]); ci=[]
        for f in ['aadhaar','pan','credit']:
            if not os.path.exists(os.path.join(CARDS,'sample_%s_card.jpg'%f)): continue
            im=cv2.cvtColor(cv2.imread(os.path.join(CARDS,'sample_%s_card.jpg'%f)),cv2.COLOR_BGR2RGB)
            q,c=read_heat(net(torch.from_numpy(prep(im))[None])[0].numpy()); ci.append(0 if q is None else quad_iou(q,cq))
    net.train()
    extra=(('cards',round(float(np.mean(ci)),3) if ci else None,'neg_minpeak_max',round(float(negpk.max()),2),'neg>=0.6',int((negpk>=0.6).sum())))
    if EXTRA: extra+=('area',round(float(np.mean(areas)),3),'neg_area_max',round(float(neg[:,4].flatten(1).mean(1).max()),3))
    return extra,np.mean([a for a,_,_ in r]),sum(c>=0.8 for _,c,_ in r),{g:round(float(np.mean([a for a,_,gg in r if gg==g])),3) for g in set(x[2] for x in r)}
def mask_iou(m,q,n=H):
    """Overlap of the area map (0.5 and up) with a marked page."""
    A=m>=0.5; B=np.zeros((n,n),np.uint8); cv2.fillPoly(B,[np.round(np.clip(q,0,1)*(n-1)).astype(np.int32)],1); B=B>0
    u=(A|B).sum(); return (A&B).sum()/u if u else 0
def widen(net,n):
    """Gives the last layer n output maps: the four corner maps keep their weights, the new ones start near zero."""
    name,old=[(k,m) for k,m in net.named_modules() if isinstance(m,torch.nn.Conv2d) and m.out_channels==4][-1]
    new=torch.nn.Conv2d(old.in_channels,n,old.kernel_size,old.stride,old.padding)
    with torch.no_grad():
        new.weight.normal_(0,0.01); new.bias.fill_(-2.0)
        new.weight[:4]=old.weight; new.bias[:4]=old.bias
    parent=net
    for part in name.split('.')[:-1]: parent=getattr(parent,part)
    setattr(parent,name.split('.')[-1],new)
net=torch.load('base.pt',weights_only=False)
if EXTRA: widen(net,CH)
RESUME=OUT+'.resume'   # written every 250 steps, so a run that was cut off carries on where it stopped
state=torch.load(RESUME,weights_only=False) if os.path.exists(RESUME) else None
if state: net=state['net']
net.train()
opt=torch.optim.AdamW(net.parameters(),3e-4,weight_decay=1e-4)
sched=torch.optim.lr_scheduler.OneCycleLR(opt,3e-4,total_steps=STEPS,pct_start=0.05)
first=1
if state: opt.load_state_dict(state['opt']); sched.load_state_dict(state['sched']); first=state['step']+1; print('carrying on from step',first,flush=True)
else: print('base',evaluate(net),flush=True)
B=8;t0=time.time();run=0
for step in range(first,STEPS+1):
    xs,ts=zip(*[sample() for _ in range(B)])
    x=torch.from_numpy(np.stack(xs));t=torch.from_numpy(np.stack(ts))
    y=net(x); w=1+9*(t>0.05).float()
    if EXTRA: w[:,4]=0.5   # the area map is dense: no extra weight for its filled cells
    loss=(w*(y-t)**2).mean()
    opt.zero_grad();loss.backward();opt.step();sched.step(); run=0.98*run+0.02*loss.item()
    if step%250==0 or step==STEPS:
        print(step,'%.0fs'%(time.time()-t0),'loss %.4f'%run,evaluate(net),flush=True); torch.save(net,OUT)
        torch.save({'step':step,'net':net,'opt':opt.state_dict(),'sched':sched.state_dict()},RESUME)
if os.path.exists(RESUME): os.remove(RESUME)
