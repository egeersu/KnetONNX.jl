KL = include("./KnetLayers/src/KnetLayers.jl")
onnx_utils = include("./onnx_utils.jl")

function ONNXtoGraph(file)
    """
    Given the path of an ONNX file, construct its graph.
    """
    f = readproto(open(file), Proto.ModelProto());
    convert(f).graph
end

function PrintGraph(g)
    """
    Prints the ONNX graph.
    """
    ops = [] # operator list
    println("model inputs: ", (x->x.name).(g.input))
    println("model outputs: ", (x->x.name).(g.output))
    for (i, node) in enumerate(g.node)
        if join(node.op_type) ∉ ops
            push!(ops, join(node.op_type))
        end
        print("(op", i, ") ", node.op_type)
        println()
        for (i, input) in enumerate(node.input)
            println("\tinput", i, ": " , input)
        end
        for (i, output) in enumerate(node.output)
            println("\toutput", i, ": " , output)
        end
    end
    println("Operator list: ", ops)
end

function convert(node, g)
    """
    Given a node, calls the appropriate constructor for the corresponding (args, layer, outs)
    """
    if node.op_type == "Add"; return converter_add(node, g); end
    if node.op_type == "AveragePool"; return converter_avgpool(node,g); end
    if node.op_type == "BatchNormalization"; return converter_batchnorm(node, g); end
    if node.op_type == "Cast"; return converter_cast(node,g); end
    if node.op_type == "Concat"; return converter_concat(node,g); end
    if node.op_type == "Constant"; return converter_constant(node, g); end
    if node.op_type == "ConstantOfShape"; return converter_constantOfShape(node, g); end
    if node.op_type == "Conv"; return converter_cnn(node,g); end
    if node.op_type == "Div"; return converter_div(node,g); end
    if node.op_type == "Dropout"; return converter_dropout(node,g); end
    if node.op_type == "Flatten"; return converter_flatten(node,g); end
    if node.op_type == "Gather"; return converter_gather(node,g); end
    if node.op_type == "Gemm"; return converter_gemm(node, g); end
    if node.op_type == "GlobalAveragePool"; return converter_globalAveragePool(node, g); end
    if node.op_type == "Identity"; return converter_identity(node, g); end
    if node.op_type == "LeakyRelu"; return converter_leakyrelu(node,g); end
    if node.op_type == "MatMul"; return converter_matmul(node,g); end
    if node.op_type == "MaxPool"; return converter_maxpool(node,g); end
    if node.op_type == "Mul"; return converter_mul(node,g); end
    if node.op_type == "Relu"; return converter_relu(node, g); end
    if node.op_type == "Reshape"; return converter_reshape(node, g); end
    if node.op_type == "RNN"; return converter_rnn(node, g);
    if node.op_type == "Shape"; return converter_shape(node, g); end
    if node.op_type == "Softmax"; return converter_softmax(node, g); end
    if node.op_type == "Slice"; return converter_slice(node, g); end
    if node.op_type == "Sub"; return converter_sub(node,g); end
    if node.op_type == "Squeeze"; return converter_squeeze(node, g); end
    if node.op_type == "Transpose"; return converter_transpose(node,g); end
    if node.op_type == "Unsqueeze"; return converter_unsqueeze(node,g); end
    else; println("ONNX Operation not yet implemented: ", node.op_type);
    end
end

# Unit Layer for Testing
struct dummy_layer
end
(d::dummy_layer)(x) = x


function converter_rnn(node, g)
    return (node.input, dummy_layer(), node.output)
end

# TODO: convert all onnx params to knet params (use convert_params(w))
"""
Converters Begin Here
# A converter's inputs: graph node and the graph
# they return 3 elements:
    # - args:  the names of the tensors that will be needed for the calculations. These are just the names: strings.
    # - layer: a KnetLayer will be constructed. If the weights are in the initializer, the layer will be modified with them.
    # - outs:  the names of the tensors that are the outputs of the calculations. These are just the names: strings.
"""

# ADD
function converter_add(node, g)
    args = node.input
    outs = node.output
    layer = KL.Add()
    return (args, layer, outs)
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

# BATCHNORM
function converter_batchnorm(node, g)
    momentum = node.attribute[:momentum]
    epsilon = node.attribute[:epsilon]

    scale = g.initializer[node.input[2]]
    B = g.initializer[node.input[3]]
    mean = g.initializer[node.input[4]]
    variance = g.initializer[node.input[5]]

    X = node.input[1]
    outs = node.output
    layer = KL.BatchNorm(length(scale); momentum=momentum, mean=mean, var=variance)
    (X, layer, outs)
end

# CAST
function converter_cast(node, g)
    args = node.input
    outs = node.output
    to = titlecase(node.attribute[:to]) # ONNX use uppercase but Julia use capitalize on data types
    layer = KL.Cast(to)
    (args, layer, outs)
end

# CONCAT
function converter_concat(node, g)
    args = node.input
    outs = node.output
    axis = node.attribute[:axis]
    layer = KL.Concat(axis)
    (args, layer, outs)
end

# CONSTANT
function converter_constant(node, g)
    args = node.input
    outs = node.output
    onnx_constant_value = node.attribute[:value]
    julia_constant_value = onnx_utils.UInt8toFloat32(onnx_constant_value)
    layer = KL.constant_layer(julia_constant_value)
    return (args, layer, outs)
end

function converter_ConstantOfShape(node, g)
    args = node.input
    outs = node.output
    onnx_constant_value = node.attribute[:value]
    julia_constant_value = onnx_utils.UInt8toFloat32(onnx_constant_value)
    layer = KL.ConstantOfShape(julia_constant_value[1])
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

#Div
function converter_div(node, g)
    args = node.input
    outs = node.output
    layer = KL.Div()
    (args, layer, outs)
end

# DROPOUT
function converter_dropout(node, g)
    args = node.input
    outs = node.output
    layer = KL.Dropout(p = node.attribute[:ratio])
    (args, layer, outs)
end

# Exponential
function converter_exp(node, g)
    args = node.input
    outs = node.output
    layer = KL.Exp()
    (args, layer, outs)
end

# FLATTEN
function converter_flatten(node, g)
    args = node.input
    outs = node.output
    layer = KL.Flatten()
    (args, layer, outs)
end


# Gather
function converter_gather(node, g)
    args = node.input
    outs = node.output
    axis = node.attribute[:axis] == nothing ? 1 : node.attribute[:axis] + 1 # +1 is for Julia
    layer = KL.Gather(axis)
    (args, layer, outs)
end

# GEMM - trains bias also for gemm that is not a linear layer, fix that, write new gemm and a separate linear
function converter_gemm(node, g)
    input1 = node.input[1]

    #the layer is a Knet Layer
    layer = KnetOnnx.KnetLayers.Linear(input=1,output=1)

    # use g.initializer to modify KnetLayer
    w_name = node.input[2]
    b_name = length(node.input) >= 3 ? node.input[3] : 0
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

# GlobalAveragePool
function converter_globalAveragePool(node, g)
    args = node.input
    layer = KL.Pool()
    outs = node.output
    (args, layer, outs)
end

# Identity
function converter_identity(node, g)
    args = node.input
    layer = identity()
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

# MatMul
function converter_matmul(node, g)
    args = node.input
    layer = KL.MatMul()
    outs = node.output
    (args, layer, outs)
end

# MaxPool
#currently treating [1,1,1,1] padding as an integer 1, same for
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

"""
Mul Converter
"""
function converter_mul(node,g)
    args = node.input
    layer = KL.Mul()
    outs = node.output
    (args, layer, outs)
end

# RELU - done
function converter_relu(node, g)
    args = node.input
    layer = KL.ReLU()
    outs = node.output
    (args, layer, outs)
end

"""
Reshape
"""
function converter_reshape(node, g)
    data = node.input[1]
    shape = node.input[2]
    layer = KL.Reshape(shape)
    outs = node.output
    (args, layer, outs)
end

# SHAPE
function converter_shape(node, g)
    args = node.input
    outs = node.output
    layer = KL.shape_layer()
    (args, layer, outs)
end

"""
SoftMax
The operator computes the softmax (normalized exponential) values for each layer in the batch of the given input.
"""
function converter_softmax(node, g)
    args = node.input
    axis = node.attribute[:axis] == nothing ? 1 : node.attribute[:axis] # default axis = 1
    layer = KL.SoftMax(axis)
    outs = node.output
    (args, layer, outs)
end

"""
Slice
"""
function converter_slice(node, g)
    println("Slice not implemented yet!")
    data = node.input[1]
    starts = node.input[2]
    ends = node.input[3]
    axes = node.input[4]
    steps = node.input[5]
    layer = KL.Slice()
    outs = node.output
    (args, layer, outs)
end

"""
Sub
"""
function converter_sub(node,g)
    args = node.input
    layer = KL.Sub()
    outs = node.output
    (args, layer, outs)
end

# SQUEEZE
function converter_squeeze(node, g)
    args = node.input
    outs = node.output
    layer = KL.squeeze_layer(node.attribute[:axes])
    (args, layer, outs)
end

function converter_transpose(node, g)
    args = node.input
    outs = node.output
    layer = KL.Transpose(node.attribute[:perm] .+ 1) # +1 for julia index
    (args, layer, outs)
end

# UNSQUEEZE
function converter_unsqueeze(node, g)
    args = node.input
    outs = node.output
    layer = KL.unsqueeze_layer(node.attribute[:axes])
    (args, layer, outs)
end

# Node to's

# BATCHNORM
function node_to_batchnorm(node, g)
    momentum = node.attribute[:momentum]
    epsilon = node.attribute[:epsilon]

    scale = g.initializer[node.input[2]]
    B = g.initializer[node.input[3]]
    mean = g.initializer[node.input[4]]
    variance = g.initializer[node.input[5]]

    KL.BatchNorm(length(scale); momentum=momentum, mean=mean, var=variance)
end

# RNN
function node_to_RNN(node, g)
    activations = node.attribute[:activations]
    hidden_size = node.attribute[:hidden_size]
end
