"""Writes a trained model as ONNX and checks it against the PyTorch model.

Usage: python3 export.py MODEL.pt OUT.onnx [MAPS]
  MAPS  how many of the model's output maps to keep, counted from the first (default: all).
        The app reads five: four corners and the page's area. The sixth, the page's outline,
        only helps in training.
"""
import sys,torch,onnx,onnxruntime as ort,numpy as np
net=torch.load(sys.argv[1],weights_only=False).eval()
keep=int(sys.argv[3]) if len(sys.argv)>3 else None
class First(torch.nn.Module):
    def __init__(self,net,n): super().__init__(); self.net=net; self.n=n
    def forward(self,x): return self.net(x)[:,:self.n]
if keep: net=First(net,keep).eval()
x=torch.rand(1,3,256,256)
torch.onnx.export(net,x,sys.argv[2],input_names=['img'],output_names=['heatmap'],opset_version=16,dynamo=False)
m=onnx.load(sys.argv[2]); onnx.checker.check_model(m)
s=ort.InferenceSession(sys.argv[2]); r=s.run(None,{'img':x.numpy()})[0]
with torch.no_grad(): t=net(x).numpy()
print(r.shape, np.abs(r-t).max())
