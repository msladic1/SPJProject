include("quant_types.jl")

function calculate_shared_scale(row::AbstractArray{Float32})::Float64
    emaxelem = 127 
    shared_exp = floor(log2(maximum(abs.(row))))

    scale_emax = 2^(8 - 1) - 1
    shared_exp = shared_exp > scale_emax ? NaN : shared_exp
    shared_exp = shared_exp < -scale_emax ? float(-scale_emax) : shared_exp

    emax = emaxelem^floor(log2(maximum(abs.(row))))

    shared_exp = shared_exp - emax
    
    return 2^shared_exp
end

function quantize_to_element_format(value::Float32, scale::Float64)::Int8
    value = Float32(value / scale)
    if isnan(scale) || abs(value*2^6) > typemax(Float32)
        return Int8(0)  # Handle special cases
    else
        clamp(round(value*2^6), typemin(Int8), typemax(Int8))
    end
end

function convert_to_quant_matrix(matrix::Matrix{Float32})
    quantized = zeros(Int, size(matrix, 1), size(matrix, 2))
    dequantized = zeros(Float32, size(matrix, 1), size(matrix, 2))

    for row in 1:size(matrix, 1)
        Pᵢ = []
        Vᵢ = []

        shared_scale = calculate_shared_scale(matrix[row, :])

        for col in 1:size(matrix, 2)

            Vi = matrix[row, col]
            pi = quantize_to_element_format(Vi, shared_scale)
            push!(Pᵢ, pi)

            vᵢ = isnan(shared_scale) || abs(shared_scale * pi) > typemax(Float32) ? NaN : clamp((pi / 2^6), typemin(Int8), typemax(Int8)) * shared_scale
            push!(Vᵢ, vᵢ)

        end

        quantized[row, :] = Pᵢ
        dequantized[row, :] =  Vᵢ

    end

    return quantized, dequantized
end

function pack(a::Int, b::Int)
    @assert -127 <= a <= 127 "a must be between -127 and 127 (provided: $a)"
    @assert -127 <= b <= 127 "b must be between -127 and 127 (provided: $b)"
    return UInt16((a << 8) + b)
end

origin_col_idx(j, i, NBLOCKS, BLOCKSIZE=32) = (mod1(i, NBLOCKS) - 1) * BLOCKSIZE + j
origin_row_idx(i, NBLOCKS) = fld1(i, NBLOCKS)

function pack(m::Matrix{Int64}, BLOCKSIZE=32)
    mat_size = size(m)

    HALFBLOCK = BLOCKSIZE ÷ 2 # 16
    NCOLS = mat_size[2]
    NBLOCKS = NCOLS ÷ BLOCKSIZE

    qm = Matrix{UInt16}(undef, NBLOCKS * mat_size[1], BLOCKSIZE ÷ 2)
    sgns = Matrix{UInt16}(undef, NBLOCKS * mat_size[1], BLOCKSIZE ÷ 2)

    for i in axes(qm, 1)
            row_idx = origin_row_idx(i, NBLOCKS)
        for j in axes(qm, 2)
            col_idx = origin_col_idx(j, i, NBLOCKS)

            first_sgn = 2
            second_sgn = 2
            first_val = m[row_idx, col_idx]
            second_val = m[row_idx, col_idx+HALFBLOCK]

            ########### Refactor this part ###########
            if m[row_idx, col_idx] < 0
                first_val *= -1
                first_sgn = 0
            end
            if m[row_idx, col_idx+HALFBLOCK] < 0
                second_val *= -1
                second_sgn = 0
            end
            ##########################################

            qm[i, j] = pack(first_val, second_val)
            sgns[i, j] = pack(first_sgn, second_sgn)
        end
    end

    return qm, sgns
end

# TODO: 1. Deal with negative values - DONE (made new matrices that saves in respective places of elements 0 if they are negative and 2 if they are positive)
#       2. Deal with situations when parts of matrix should be filled with 0 (size not div by 32 or BLOCKSIZE or smaller than BLOCKSIZE)

# TODO: Reorganization of noticable size is needed. Basically in quant function a vector of shared_scales by row should also be created
#       When this hex matrix is created it should consist of Chunks. Struct Chunk should have this value which consists of two UInt8 representations
#       of quantized values and a value which is scale used to quantize values in the row that value is from.