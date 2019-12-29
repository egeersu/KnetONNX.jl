####
#### Sampling
####
mutable struct Sampling{T<:Function} <: Layer
    options::NamedTuple
end

Sampling{T}(;window=2, padding=0, stride=window, mode=0, maxpoolingNanOpt=0, alpha=1) where T <: Function =
    Sampling{T}((window=window, padding=padding, stride=stride, mode=mode, maxpoolingNanOpt=maxpoolingNanOpt, alpha=alpha))

(m::Sampling{typeof(pool)})(x)   =  pool(x;m.options...)
(m::Sampling{typeof(unpool)})(x) =  unpool(x;m.options...)

#reshaped so that vgg16 works
#(m::Sampling{typeof(pool)})(x)   =  pool(reshape(x, (size(x)[1:3]..., 1));m.options...)
#(m::Sampling{typeof(unpool)})(x) =  unpool(x;m.options...)

"""
    Pool(kwargs...)
    (::Sampling{typeof(pool)})(x)

Compute pooling of input values (i.e., the maximum or average of several adjacent
values) to produce an output with smaller height and/or width.

Currently 4 or 5 dimensional KnetArrays with Float32 or Float64 entries are
supported. If x has dimensions (X1,X2,...,I,N), the result y will have dimensions
(Y1,Y2,...,I,N) where

Yi=1+floor((Xi+2*padding[i]-window[i])/stride[i])

Here I is the number of input channels, N is the number of instances, and Xi,Yi
are spatial dimensions. window, padding and stride are keyword arguments that can
be specified as a single number (in which case they apply to all dimensions), or
an array/tuple with entries for each spatial dimension.

Keywords:

* window=2: the pooling window size for each dimension.

* padding=0: the number of extra zeros implicitly concatenated at the
start and at the end of each dimension.

* stride=window: the number of elements to slide to reach the next pooling
window.

* mode=0: 0 for max, 1 for average including padded values, 2 for average
excluding padded values.

* maxpoolingNanOpt=0: Nan numbers are not propagated if 0, they are
propagated if 1.

* alpha=1: can be used to scale the result.

"""
Pool(;o...) = Sampling{typeof(pool)}(;o...)

"""
    UnPool(kwargs...)
    (::Sampling{typeof(unpool)})(x)

    Reverse of pooling. It has same kwargs with Pool

    x == pool(unpool(x;o...); o...)
"""
UnPool(;o...) = Sampling{typeof(unpool)}(;o...)
####
#### Filtering
####
mutable struct Filtering{T<:Function} <: Layer
    weight
    bias
    activation
    options::NamedTuple
end

function Filtering{T}(;height::Integer, width::Integer, inout::Pair=1=>1,
                         winit=xavier, binit=zeros, atype=arrtype,
                         activation=ReLU(), opts...) where T <: Function
    wsize = T===typeof(conv4) ? inout : reverse(inout)
    w = param(height,width,wsize...; init=winit, atype=atype)
    b = binit !== nothing ? param(1,1,inout[2],1; init=binit, atype=atype) : nothing
    Filtering{T}(w, b, activation; opts...)
end

Filtering{T}(w, b, activation; stride=1, padding=0, mode=0, dilation=1, alpha=1) where T <: Function =
    Filtering{T}(w, b, activation, (stride=stride, dilation=dilation, mode=mode, alpha=alpha, padding=padding))

(m::Filtering{typeof(conv4)})(x) =
     postConv(m, conv4(m.weight, make4D(x); m.options...), ndims(x))

(m::Filtering{typeof(deconv4)})(x) =
     postConv(m, deconv4(m.weight, make4D(x); m.options...), ndims(x))
"""
    Conv(;height=filterHeight, width=filterWidth, inout = 1 => 1, kwargs...)

Creates and convolutional layer `Filtering{typeof(conv4)}` according to given filter dimensions.

    (m::Filtering{typeof(conv4)})(x) #forward run

If `m.w` has dimensions `(W1,W2,...,I,O)` and
`x` has dimensions `(X1,X2,...,I,N)`, the result `y` will have
dimensions `(Y1,Y2,...,O,N)` where

    Yi=1+floor((Xi+2*padding[i]-Wi)/stride[i])

Here `I` is the number of input channels, `O` is the number of output channels, `N` is the number of instances,
and `Wi,Xi,Yi` are spatial dimensions. `padding` and `stride` are
keyword arguments that can be specified as a single number (in which case they apply to all dimensions),
or an tuple with entries for each spatial dimension.

# Keywords
* `inout=input_channels => output_channels`
* `activation=identity`: nonlinear function applied after convolution
* `pool=nothing`: Pooling layer or window size of pooling
* `winit=xavier`: weight initialization distribution
* `bias=zeros`: bias initialization distribution
* `padding=0`: the number of extra zeros implicitly concatenated at the start and at the end of each dimension.
* `stride=1`: the number of elements to slide to reach the next filtering window.
* `upscale=1`: upscale factor for each dimension.
* `mode=0`: 0 for convolution and 1 for cross-correlation.
* `alpha=1`: can be used to scale the result.
* `handle`: handle to a previously created cuDNN context. Defaults to a Knet allocated handle.

"""
Conv(;height::Int, width::Int, o...) = Filtering{typeof(conv4)}(;height=height, width=width, o...)

"""
    DeConv(;height=filterHeight, width=filterWidth, inout=1=>1, kwargs...)

Creates and deconvolutional layer `Filtering{typeof(deconv4)}`  according to given filter dimensions.


    (m::Filtering{typeof(deconv4)})(x) #forward run

If `m.w` has dimensions `(W1,W2,...,I,O)` and
`x` has dimensions `(X1,X2,...,I,N)`, the result `y` will have
dimensions `(Y1,Y2,...,O,N)` where

    Yi = Wi+stride[i](Xi-1)-2padding[i]

Here `I` is the number of input channels, `O` is the number of output channels, `N` is the number of instances,
and `Wi,Xi,Yi` are spatial dimensions. `padding` and `stride` are
keyword arguments that can be specified as a single number (in which case they apply to all dimensions),
or an tuple with entries for each spatial dimension.

# Keywords
* `inout=input_channels => output_channels`
* `activation=identity`: nonlinear function applied after convolution
* `unpool=nothing`: Unpooling layer or window size of unpooling
* `winit=xavier`: weight initialization distribution
* `bias=zeros`: bias initialization distribution
* `padding=0`: the number of extra zeros implicitly concatenated at the start and at the end of each dimension.
* `stride=1`: the number of elements to slide to reach the next filtering window.
* `upscale=1`: upscale factor for each dimension.
* `mode=0`: 0 for convolution and 1 for cross-correlation.
* `alpha=1`: can be used to scale the result.
* `handle`: handle to a previously created cuDNN context. Defaults to a Knet allocated handle.
"""
DeConv(;height::Integer, width::Integer, o...) = Filtering{typeof(deconv4)}(;height=height, width=width, o...)

###
### Utils
###
function make4D(x)
    n = ndims(x)
    @assert n < 5 "filtering layers currently supports 4 dimensional arrays"
    n == 4 ? x : reshape(x,size(x)...,ntuple(x->1, 4-n)...)
end

function postConv(m::Filtering, y, dims)
    if m.bias !== nothing
        y = y .+ m.bias
    end
    if m.activation !== nothing
        y = m.activation(y)
    end
    return dims>3 ? y : reshape(y,size(y)[1:dims])
end
