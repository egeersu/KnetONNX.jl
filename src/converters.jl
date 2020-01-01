KL = include("./KnetLayers/src/KnetLayers.jl")

# ONNX file path -> Graph
function ONNXtoGraph(file)
    f = readproto(open(file), Proto.ModelProto());
    convert(f).graph
end

# Prints the Graph in a pretty format
function PrintGraph(g)
    println("model inputs: ", (x->x.name).(g.input))
    println("model outputs: ", (x->x.name).(g.output))
    for (i, node) in enumerate(g.node)
        print("(op", i, ") ", node.op_type)
        println()
        for (i, input) in enumerate(node.input)
            println("\tinput", i, ": " , input)
        end
        for (i, output) in enumerate(node.output)
            println("\toutput", i, ": " , output)
        end
    end
end

"""
Given a node, calls the appropriate constructor for the corresponding (args, layer, outs)
"""
function convert(node, g)
    if node.op_type == "Gemm"; return converter_gemm(node, g); end
    if node.op_type == "Add"; return converter_add(node, g); end
    if node.op_type == "Relu"; return converter_relu(node, g); end
    if node.op_type == "LeakyRelu"; return converter_leakyrelu(node,g); end
    if node.op_type == "Conv"; return converter_cnn(node,g); end
    if node.op_type == "MaxPool"; return converter_maxpool(node,g); end
    if node.op_type == "AveragePool"; return converter_avgpool(node,g); end
    if node.op_type == "Dropout"; return converter_dropout(node,g); end
    if node.op_type == "Flatten"; return converter_flatten(node,g); end
    if node.op_type == "Constant"; return converter_constant(node, g); end
    if node.op_type == "Shape"; return converter_shape(node, g); end
    if node.op_type == "Squeeze"; return converter_squeeze(node, g); end
    if node.op_type == "Unsqueeze"; return converter_unsqueeze(node,g); end
    if node.op_type == "Concat"; return converter_concat(node,g); end
    if node.op_type == "RNN"; return converter_rnn(node, g);
    else; println("ONNX Operation not yet implemented: ", node.op_type);
    end

end

function converter_rnn(node, g)
    1
end

## TODO: convert all onnx params to knet params (use convert_params(w))
"""
Converters Begin Here
# A converter's inputs: graph node and the graph
# they return 3 elements:
    # - args:  the names of the tensors that will be needed for the calculations. These are just the names: strings.
    # - layer: a KnetLayer will be constructed. If the weights are in the initializer, the layer will be modified with them.
    # - outs:  the names of the tensors that are the outputs of the calculations. These are just the names: strings.

"""

# GEMM - trains bias also for gemm that is not a linear layer, fix that, write new gemm and a separate linear

function converter_gemm(node, g)
    input1 = node.input[1]

    #the layer is a Knet Layer
    layer = KnetOnnx.KnetLayers.Linear(input=1,output=1)

    # use g.initializer to modify KnetLayer
    w_name = node.input[2]
    b_name = node.input[3]
    w = g.initializer[w_name]
    w = transpose(w)
    b = g.initializer[b_name]

    w = KnetOnnx.KnetLayers.ConvertParams(w)
    b = KnetOnnx.KnetLayers.ConvertParams(b)

    layer.bias = b
    layer.mult.weight = w

    # return input tensor NAMES, it is called args: [input1, ...]
    # you can take the inputs from model.tensors using these names
    args = [input1]
    outs = [node]

    # returns these 3, use these to create ModelLayer
    (args, layer, node.output)
end

# ADD - done
# move this to KnetLayers
struct AddLayer; end
(a::AddLayer)(x,y) = x+y

function converter_add(node, g)
    args = node.input
    outs = node.output
    layer = AddLayer()
    return (args, layer, outs)
end

# RELU - done
function converter_relu(node, g)
    args = node.input
    layer = KL.ReLU()
    outs = node.output
    (args, layer, outs)
end

# LEAKY RELU - done
function converter_leakyrelu(node, g)
    args = node.input
    alpha = node.attribute[:alpha]
    layer = KL.LeakyReLU(alpha)
    outs = node.output
    (args, layer, outs)
end

# CONV
#conv1 = KnetOnnx.KnetLayers.Conv(;height=3, width=3, inout = 3=>64)
#currently treating [1,1,1,1] padding as an integer 1, same for stride
function converter_cnn(node, g)
    args = [node.input[1]]
    out = node.output

    padding = 0
    strides = 0
    if :pads in keys(node.attribute); padding = node.attribute[:pads][1]; end
    if :strides in keys(node.attribute); stride = node.attribute[:strides][1]; end

    layer = KnetOnnx.KL.Conv(height=1,width=1,inout=1=>1; padding = padding, stride = stride)

    if length(node.input) >= 2
        w_name = node.input[2]
        w = g.initializer[w_name]
        #might cause a problem later on with different convs
        layer.weight = w

    end
    if length(node.input) >= 3
        b_name = node.input[3]
        b = g.initializer[b_name]
        layer.bias = reshape(b, 1, 1, size(b)[1], 1)
    end
    (args, layer, out)
end

# MaxPool
#currently treating [1,1,1,1] padding as an integer 1, same for stride
function converter_maxpool(node, g)
    args = node.input
    outs = node.output
    stride = 0
    padding = 0

    if :pads in keys(node.attribute); padding = node.attribute[:pads][1]; end
    if :strides in keys(node.attribute); stride = node.attribute[:strides][1]; end

    layer = KL.Pool(padding=padding, stride=stride, mode=0)
    (args, layer, outs)
end

# AveragePool
function converter_avgpool(node, g)
    args = node.input
    outs = node.output
    stride = 0
    padding = 0

    if :pads in keys(node.attribute); padding = node.attribute[:pads][1]; end
    if :strides in keys(node.attribute); stride = node.attribute[:strides][1]; end

    layer = KL.Pool(padding=padding, stride=stride, mode=1)
    (args, layer, outs)
end

# DROPOUT
function converter_dropout(node, g)
    args = node.input
    outs = node.output
    layer = KL.Dropout(p = node.attribute[:ratio])
    (args, layer, outs)
end


# FLATTEN
function converter_flatten(node, g)
    args = node.input
    outs = node.output
    layer = KL.Flatten()
    (args, layer, outs)
end


# BATCHNORM
function node_to_batchnorm(node, g)
    momentum = node.attribute[:momentum]
    epsilon = node.attribute[:epsilon]
    spatial = node.attribute[:spatial]

    scale = g.initializer[node.input[2]]
    B = g.initializer[node.input[3]]
    mean = g.initializer[node.input[4]]
    variance = g.initializer[node.input[5]]

    KL.BatchNorm(length(scale); momentum=momentum, mean=mean, var=variance)
end


# IMAGE SCALER

function node_to_imagescaler(node, g)
    bias = node.attribute[:bias]
    scale = node.attribute[:scale]
    #ScalerLayer(x) = scale .* x
end


# RNN

function node_to_RNN(node, g)
    activations = node.attribute[:activations]
    hidden_size = node.attribute[:hidden_size]
end

# CONSTANT
mutable struct constant_layer
    data
end

(l::constant_layer)() = l.data

function UInt8toFloat32(val)
    dims = val.dims
    data = val.raw_data
    indices = collect(1:4:length(data))
    data_list = []
    for i in indices; push!(data_list, float_from_bitstring(Float32, generate_bitstring(data[i:i+3]))); end;
    new_size = tuple(val.dims...)
    reshape(data_list, new_size)
end

function generate_bitstring(raw_4)
    bits = ""
    for i in reverse(raw_4); bits *= bitstring(i); end
    bits
end

function float_from_bitstring(::Type{T}, str::String) where {T<:Base.IEEEFloat}
    unsignedbits = Meta.parse(string("0b", str))
    thefloat  = reinterpret(T, unsignedbits)
    return thefloat
end

function converter_constant(node, g)
    args = node.input
    outs = node.output
    layer = constant_layer(UInt8toFloat32(node.attribute[:value]))
    return (args, layer, outs)
end

# SHAPE
mutable struct shape_layer
end

(l::shape_layer)(x) = size(x)

function converter_shape(node, g)
    args = node.input
    outs = node.output
    layer = shape_layer()
    (args, layer, outs)
end


# UNSQUEEZE
function converter_unsqueeze(node)
    args = node.input
    outs = node.output
    layer = unsqueeze_layer(node.attribute[:axes])
    (args, layer, outs)
end

mutable struct unsqueeze_layer
    axes
end

function (u::unsqueeze_layer)(x)
    data = [t for t in size(x)]
    axes = [a+1 for a in u.axes]
    for i in axes; insert!(data, i, 1); end
    new_size = (data...,)
    reshape(x, new_size)
end

# SQUEEZE
function converter_squeeze(node)
    args = node.input
    outs = node.output
    layer = squeeze_layer(node.attribute[:axes])
    (args, layer, outs)
end

mutable struct squeeze_layer
    axes
end

function (s::squeeze_layer)(x)
    new_size = []
    for (i, dim) in enumerate(size(x))
        if dim>1; push!(new_size, dim); end
    end
    new_size = (new_size...,)
    reshape(x, new_size)
end

# CONCAT
mutable struct concat_layer
    axis
end

function (l::concat_layer)(args...)
    if l.axis == 0; return vcat(args...);
    else; return hcat(args...); end
end

function converter_concat(node, g)
    args = node.input
    outs = node.output
    axis = node.attribute[:axis]
    layer = concat_layer(axis)
    (args, layer, outs)
end
