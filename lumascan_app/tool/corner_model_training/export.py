import sys,torch,onnx,onnxruntime as ort,numpy as np
net=torch.load(sys.argv[1],weights_only=False).eval()
x=torch.rand(1,3,256,256)
torch.onnx.export(net,x,sys.argv[2],input_names=['img'],output_names=['heatmap'],opset_version=16,dynamo=False)
m=onnx.load(sys.argv[2]); onnx.checker.check_model(m)
s=ort.InferenceSession(sys.argv[2]); r=s.run(None,{'img':x.numpy()})[0]
with torch.no_grad(): t=net(x).numpy()
print(r.shape, np.abs(r-t).max())
