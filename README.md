<img src="https://github.com/onnx/onnx/blob/master/docs/ONNX_logo_main.png?raw=true" width="400">

KnetONNX lets you read an ONNX file and create a Knet Model that can be used for prediction, re-designed or re-trained.

If you are planning to move your models from PyTorch or Tensorflow to Knet, or simply desiring to play with popular pre-trained neural networks: KnetONNX provides that functionality.

[Open Neural Network Exchange (ONNX)](https://onnx.ai/)
 is a community project created by Facebook and Microsoft. It provides a definition of an extensible computation graph model, as well as definitions of built-in operators and standard data types.

Operators are implemented externally to the graph, but the set of built-in operators are portable across frameworks. Every framework supporting ONNX will provide implementations of these operators on the applicable data types.

Although not all operations are implemented yet, visit ONNX's [model zoo](https://github.com/onnx/models) to download pre-trained, state-of-the-art models in the ONNX format.

Once you download the ONNX file, call KnetModel() with the ONNX file's path to create the model.

## Tutorial

Here is how you create the Knet model corresponding to an ONNX file and perform a forward pass:

```julia
using Knet, KnetONNX

#provide the ONNX file's path
model = KnetModel("vgg.onnx");

#dummy input for prediction
x = ones(Float32,224,224,3,10)

#call KnetModel object with the model input
model(x) #the output is a 1000×10 Array{Float32,2}
```
For a more detailed tutorial please refer to [MLP_Tutorial](https://github.com/egeersu/KnetONNX/blob/master/MLP_Tutorial.ipynb)

## Supported Operations
- [x] ReLU
- [x] LeakyReLU
- [x] Conv
- [x] MaxPool
- [x] Dropout
- [x] Flatten
- [x] Gemm
- [x] Add
- [x] BatchNormalization
- [x] ImageScaler
- [x] RNN
- [x] Unsqueeze
- [x] Squeeze
- [x] Concat
- [x] ConstantOfShape
- [x] Shape
- [x] Constant

## Collaboration
Here are some cool ideas if you want to collaborate:
- Export functionality. This would be a tough problem so feel free to get in contact.
- Adding a new [KnetLayer.](https://github.com/egeersu/KnetONNX/tree/master/KnetLayers)
- Adding a new [Converter:](https://github.com/egeersu/KnetONNX/blob/master/converters.jl) (ONNX Operator -> KnetLayer)
- Testing ONNX models from the [zoo](https://github.com/onnx/models) and sending bug reports.
