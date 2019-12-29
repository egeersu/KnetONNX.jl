"""
    Multiply(input=inputDimension, output=outputDimension, winit=xavier, atype=KnetLayers.arrtype)

Creates a matrix multiplication layer based on `inputDimension` and `outputDimension`.
    (m::Multiply) = m.w * x

By default parameters initialized with xavier, you may change it with `winit` argument.

# Keywords
* `input=inputDimension`: input dimension
* `output=outputDimension`: output dimension
* `winit=xavier`: weight initialization distribution
* `atype=KnetLayers.arrtype` : array type for parameters.
   Default value is KnetArray{Float32} if you have gpu device. Otherwise it is Array{Float32}
"""
mutable struct Multiply <: Layer
    weight
end

Multiply(;input::Int, output::Int, winit=xavier, atype=arrtype) =  Multiply(param(output, input; init=winit, atype=atype))

(m::Multiply)(x::Array{<:Integer}) = m.weight[:,x] # Lookup (EmbedLayer)

# TODO: Find a faster (or compound) way for tensor-product
function (m::Multiply)(x; keepsize=true)
    if ndims(x) > 2
        s = size(x)
        y = m.weight * reshape(x, s[1], prod(s[2:end]))
        return (keepsize ? reshape(y, size(y, 1), s[2:end]...) : y)
    else
        return m.weight * x
    end
end

"""
    Embed(input=inputSize, output=embedSize, winit=xavier, atype=KnetLayers.arrtype)
Creates an embedding layer according to given `inputSize` and `embedSize` where `inputSize` is your number of unique items you want to embed, and `embedSize` is the size of output vectors.
By default parameters initialized with xavier, you yam change it with `winit` argument.

    (m::Embed)(x::Array{T}) where T<:Integer
    (m::Embed)(x; keepsize=true)


Embed objects are callable with an input which is either and integer array
(one hot encoding) or an N-dimensional matrix. For N-dimensional matrix,
`size(x,1)==inputSize`

# Keywords

* `input=inputDimension`: input dimension
* `output=embeddingDimension`: output dimension
* `winit=xavier`: weight initialization distribution
* `atype=KnetLayers.arrtype` : array type for parameters.
   Default value is KnetArray{Float32} if you have gpu device. Otherwise it is Array{Float32}

"""
Embed = Multiply

# TODO: find a better documentation style e.g put input : and output etc.
# Input: Type of its input is an ::Array{T} where T<: Integer

"""
Gemm
"""

mutable struct Gemm 
    alpha
    beta
    transA
    transB
end

# inputs: matrices to be multiplied, handle C somehow (maybe zeros() with the same size as A*B)
function (g::Gemm)(A, B, C)
    if g.transA != 0; A = transpose(A); end
    if g.transB != 0; B = transpose(B); end
    g.alpha * A * B + (g.beta * C)    
end

"""
    Linear(input=inputSize, output=outputSize, winit=xavier, binit=zeros, atype=KnetLayers.arrtype)

Creates and linear layer according to given `inputSize` and `outputSize`.

# Keywords
* `input=inputSize`   input dimension
* `output=outputSize` output dimension
* `winit=xavier`: weight initialization distribution
* `bias=zeros`: bias initialization distribution
* `atype=KnetLayers.arrtype` : array type for parameters.
   Default value is KnetArray{Float32} if you have gpu device. Otherwise it is Array{Float32}
"""
mutable struct Linear <: Layer
    mult::Multiply
    bias
end

function Linear(;input::Int, output::Int, winit=xavier, binit=zeros, atype=arrtype)
    Linear(Multiply(input=input, output=output, winit=winit, atype=atype),param(output, init=binit, atype=atype))
end

(m::Linear)(x) = m.mult(x) .+ m.bias

"""
    Dense(input=inputSize, output=outputSize, activation=ReLU(), winit=xavier, binit=zeros, atype=KnetLayers.arrtype)

Creates and deense layer according to given `input=inputSize` and `output=outputSize`.
If activation is `nothing`, it acts like a `Linear` Layer.
# Keywords
* `input=inputSize`   input dimension
* `output=outputSize` output dimension
* `winit=xaiver`: weight initialization distribution
* `bias=zeros`:   bias initialization distribution
* `activation=ReLU()`  activation function(it does not broadcast) or an  activation layer
* `atype=KnetLayers.arrtype` : array type for parameters.
   Default value is KnetArray{Float32} if you have gpu device. Otherwise it is Array{Float32}
"""
mutable struct Dense <: Layer
    linear::Linear
    activation
end

function Dense(;input::Int, output::Int, activation=ReLU(), winit=xavier, binit=zeros, atype=arrtype)
    Dense(Linear(input=input, output=output, winit=winit, binit=binit, atype=atype), activation)
end

(m::Dense)(x) = m.activation===nothing ? m.linear(x) : m.activation(m.linear(x))

#TO-DO: Remove after the issue is resolved:
#https://github.com/denizyuret/Knet.jl/issues/418
"""
    BatchNorm(channels:Int;options...)
    (m::BatchNorm)(x;training=false) #forward run
# Options
* `momentum=0.1`: A real number between 0 and 1 to be used as the scale of
 last mean and variance. The existing running mean or variance is multiplied by
 (1-momentum).
* `mean=nothing': The running mean.
* `var=nothing`: The running variance.
* `meaninit=zeros`: The function used for initialize the running mean. Should either be `nothing` or
of the form `(eltype, dims...)->data`. `zeros` is a good option.
* `varinit=ones`: The function used for initialize the run
* `dataType=eltype(KnetLayers.arrtype)` : element type ∈ {Float32,Float64} for parameters. Default value is `eltype(KnetLayers.arrtype)`
* `usegpu=KnetLayers.arrtype <: KnetArray` :
# Keywords
* `training`=nothing: When training is true, the mean and variance of x are used and moments
 argument is modified if it is provided. When training is false, mean and variance
 stored in the moments argument are used. Default value is true when at least one
 of x and params is AutoGrad.Value, false otherwise.
"""
mutable struct BatchNorm <: Layer
    params
    moments::Knet.BNMoments
end

function BatchNorm(channels::Int; usegpu = arrtype <: KnetArray, dataType=eltype(arrtype), o...)
    w = bnparams(dataType,channels)
    m = bnmoments(;o...)
    BatchNorm(usegpu ? Param(KnetArray(w)) : Param(w),m)
end
(m::BatchNorm)(x;o...) = batchnorm(x,m.moments,m.params;o...)


#3D -> 2D
struct Flatten <: Layer
end

function (f::Flatten)(x)
    s = size(x)
    # batch mode (..., 1) at the end
    if s[end] == 1
        #reshape(x, :, size(x)[end-1], 1)
        reshape(x, :, size(x)[end])

    # no batch
    else
        reshape(x, :, size(x)[end])
    end
end

