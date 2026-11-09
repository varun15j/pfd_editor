import re, json, cv2, numpy as np, os

# The app folder (lumascan_app/), two levels up from this script.
R=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..')+'/'
def parse_dart(path, folder):
    src=open(R+path).read()
    out={}
    for m in re.finditer(r"'(\d\d)': \[(.*?)\],\n", src, re.S):
        qs=re.findall(r"_q\(([^)]*)\)", m.group(2))
        quads=[np.array([float(v) for v in q.split(',')]).reshape(4,2) for q in qs]
        out[m.group(1)]=quads
    files=sorted(os.listdir(R+folder))
    res=[]
    for f in files:
        k=f[:2]
        if k in out: res.append((R+folder+f, out[k], folder.split('/')[1]))
    return res
# The five handwritten notebook photos in sample_photos/, marked by hand
# (about 3% of the frame) on 2026-11-05. TL, TR, BR, BL as a fraction of the
# photo; a corner off the frame is put on the frame edge.
NOTEBOOK={'01_revision1_palindrome_lengths.jpg':[[.09,.08],[.92,.07],[.94,.94],[.13,.96]],
 '02_revision2_multiplication.jpg':[[.06,.01],[1,.02],[1,1],[.04,1]],
 '03_revision3_conversions_shapes.jpg':[[.25,.16],[1,.05],[1,1],[.12,1]],
 '04_revision4_lengths.jpg':[[.07,.2],[1,.19],[1,1],[.04,1]],
 '05_revision_grocery_table.jpg':[[.1,.05],[.82,.02],[.85,1],[.1,1]]}
def all_samples():
    s=parse_dart('test/book_detection_test.dart','sample_photos/book/')
    s+=parse_dart('test/colour_book_detection_test.dart','sample_photos/colour_book/')
    cj=json.load(open(R+'sample_photos/edge/corners.json'))
    for e in cj['samples']:
        s.append((R+'sample_photos/edge/'+e['file'],[np.array(p) for p in e['pages']],'edge'))
    for f,q in NOTEBOOK.items(): s.append((R+'sample_photos/'+f,[np.array(q,float)],'notebook'))
    return s
def is_val(i): return i%4==3
def quad_iou(a,b,n=400):
    A=np.zeros((n,n),np.uint8);B=A.copy()
    cv2.fillPoly(A,[np.round(np.clip(a,0,1)*(n-1)).astype(np.int32)],1)
    cv2.fillPoly(B,[np.round(np.clip(b,0,1)*(n-1)).astype(np.int32)],1)
    i=(A&B).sum();u=(A|B).sum();return i/u if u else 0
def read_heat(h,thr=0.3):
    pts=[];conf=1.0;size=h.shape[-1]
    for m in h[:4]:
        pk=m.max()
        if pk<thr: return None,pk
        conf=min(conf,pk);cut=max(thr,pk/2)
        ys,xs=np.nonzero(m>=cut);w=m[ys,xs]
        pts.append([ (xs*w).sum()/w.sum()/(size-1),(ys*w).sum()/w.sum()/(size-1)])
    p=np.clip(np.array(pts),0,1);c=p.mean(0)
    ang=np.arctan2(p[:,1]-c[1],p[:,0]-c[0]);p=p[np.argsort(ang)]
    st=np.argmin(p.sum(1));return np.roll(p,-st,0),conf
def prep(img):  # img RGB uint8
    x=cv2.resize(img,(256,256),interpolation=cv2.INTER_LINEAR).astype(np.float32)/255
    return x.transpose(2,0,1)
def odds_samples():
    """Six colour book photos kept out of training altogether: a fair test."""
    return parse_dart('test/edge_samples_test.dart','sample_scan_img/odds_book/')
