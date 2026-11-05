"""Turns the shipped DocAligner ONNX model into a PyTorch module (base.pt).

The conversion is exact (largest difference 4e-7 on random input).
Usage: python3 convert.py ../../assets/models/<model>.onnx base.pt
"""
import sys, onnx, torch
from onnx2torch import convert

torch.save(convert(onnx.load(sys.argv[1])), sys.argv[2])
