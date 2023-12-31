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

function convert_to_quant_matrix(matrix::Matrix{Float32})#::QuantMatrix{Int8}
    chunks = Chunk{Int8, 16}[]
    quantized = zeros(Int, size(matrix, 1), size(matrix, 2))
    dequantized = zeros(Float32, size(matrix, 1), size(matrix, 2))

    counter = 1

    for row in 1:size(matrix, 1)
        Pᵢ = []
        Vᵢ = []

        chunk_values = zeros(Int8, 16)
        reset_zeros = chunk_values
        shared_scale = calculate_shared_scale(matrix[row, :])

        for col in 1:size(matrix, 2)

            if counter == 16
                push!(chunks, Chunk{Int8, 16}(chunk_values, shared_scale, 0.0))
                chunk_values = reset_zeros
                counter = 1
            end

            Vi = matrix[row, col]
            pi = quantize_to_element_format(Vi, shared_scale)
            push!(Pᵢ, pi)

            chunk_values[counter] = pi
            counter += 1

            if counter < 16 && col == size(matrix, 2)
                push!(chunks, Chunk{Int8, 16}(chunk_values, shared_scale, 0.0))
                chunk_values = reset_zeros
                counter = 1
            end

            vᵢ = isnan(shared_scale) || abs(shared_scale * pi) > typemax(Float32) ? NaN : clamp((pi / 2^6), typemin(Int8), typemax(Int8)) * shared_scale
            push!(Vᵢ, vᵢ)
            # push!(chunks, Chunk(Int8(vᵢ), shared_scale, 0.0))  # Not sure about minimum here
        end
        quantized[row, :] = Pᵢ
        dequantized[row, :] =  Vᵢ
        #println(Pᵢ)
        #println(Vᵢ)
        # println(chunks)
        #println("-----------------------------------------------------------------------------------------------------------")
    end
    return quantized, dequantized
    #print(dequantized)
    # return QuantMatrix(hcat([chunk for chunk in chunks]...), size(matrix))
end

# IDEA: Maybe have this function (above) just return two matrices (regular) quantized and dequantized
# Then have new function to make matrix of type QuantMatrix from this matrix with quantized values
# It is easier, then to write tests and check if after dequantization values are approximately the same
# That is have one function do quantization and other one assemble QuantMatrix
# It is more readable, robust and easier to test