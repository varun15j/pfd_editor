"""Scores the whole crop: model outline when sure, else the hand-made detector.

Usage: python3 pipeline.py MODEL.pt [MODEL.pt ...]
Sets: 'held back' = every 4th marked photo (fair only for a model trained
with ALL=0), 'odds' = 6 colour book photos never trained on, 'all' = all 66.
"""
import os,sys,json,torch,cv2,numpy as np
from data import *
# detector.json: the hand-made detector's outline for each photo at 640 px,
# written by a throwaway flutter test (see README.md).
det=json.load(open(os.environ.get('DETECTOR_JSON','detector.json')))
SETS={'held back':[s for i,s in enumerate(all_samples()) if is_val(i)],'odds':odds_samples(),'all':all_samples()}
def preds(m,samples,size=640):
    net=torch.load(m,weights_only=False).eval(); out=[]
    for f,qs,g in samples:
        im=cv2.cvtColor(cv2.imread(f),cv2.COLOR_BGR2RGB); s=size/max(im.shape[:2]); im=cv2.resize(im,None,fx=s,fy=s,interpolation=cv2.INTER_AREA)
        with torch.no_grad(): h=net(torch.from_numpy(prep(im))[None])[0].numpy()
        out.append(read_heat(h))
    return out
def score(samples,P,T,smart):
    r={}
    for (f,qs,g),(q,c) in zip(samples,P):
        if q is None or c<T:
            d=det['%s|%s'%(f.split('/')[-1],'true' if smart else 'false')]; q=None if d is None else np.array(d)
        r.setdefault(g,[]).append(0 if q is None else max(quad_iou(q,t) for t in qs))
    allv=[x for v in r.values() for x in v]
    return '%.3f (n=%d, >=0.85: %d) '%(np.mean(allv),len(allv),sum(x>=0.85 for x in allv))+' '.join('%s %.3f'%(k,np.mean(v)) for k,v in sorted(r.items()))
T=float(os.environ.get('T','0.5'))
for name,samples in SETS.items():
    base=preds('base.pt',samples)
    print(name,'| hand-made only Pro  ',score(samples,base,9,True))
    print(name,'| hand-made only Basic',score(samples,base,9,False))
    print(name,'| today Pro (base model >= 0.8)',score(samples,base,0.8,True))
    for m in sys.argv[1:]:
        P=preds(m,samples)
        print(name,'|',m,'>= %.2f Pro  '%T,score(samples,P,T,True))
        print(name,'|',m,'>= %.2f Basic'%T,score(samples,P,T,False))
        P=preds(m,samples,200)
        print(name,'|',m,'model alone at 200 px, sure on %d of %d'%(sum(c>=T for q,c in P if q is not None),len(P)),
              'mean %.3f'%np.mean([0 if q is None else max(quad_iou(q,t) for t in qs) for (f,qs,g),(q,c) in zip(samples,P)]))
