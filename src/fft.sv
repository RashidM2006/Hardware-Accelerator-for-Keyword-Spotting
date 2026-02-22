// 32-Point FFT (Radix-2 Decimation-in-Time)
// Fixed-point implementation with 16-bit data width

module fft #(
    parameter int DATA_WIDTH = 16,
    parameter int FFT_SIZE = 32,
    parameter int STAGES = 5  // log2(32) = 5
)(
    input  logic                        clock,
    input  logic                        reset,
    input  logic                        valid_in,
    input  logic signed [DATA_WIDTH-1:0] data_real_in,
    input  logic signed [DATA_WIDTH-1:0] data_imag_in,
    output logic                        valid_out,
    output logic signed [DATA_WIDTH-1:0] data_real_out,
    output logic signed [DATA_WIDTH-1:0] data_imag_out,
    output logic                        ready
);

    // State machine
    typedef enum logic [2:0] {
        IDLE,
        LOAD_INPUT,
        COMPUTE,
        SYNC,
        FINAL_SYNC,
        OUTPUT
    } state_t;
    
    state_t state;
    
    // Counters and control
    logic [4:0] input_count;
    logic [5:0] output_count;  // 6 bits needed to count to 32
    logic [2:0] stage_num;
    logic [5:0] compute_count;
    
    // Data buffers - ping-pong for in-place FFT
    logic signed [DATA_WIDTH-1:0] data_real [0:FFT_SIZE-1];
    logic signed [DATA_WIDTH-1:0] data_imag [0:FFT_SIZE-1];
    logic signed [DATA_WIDTH-1:0] temp_real [0:FFT_SIZE-1];
    logic signed [DATA_WIDTH-1:0] temp_imag [0:FFT_SIZE-1];
    
    // Bit reverse function
    function automatic logic [4:0] bit_reverse(input logic [4:0] addr);
        return {addr[0], addr[1], addr[2], addr[3], addr[4]};
    endfunction
    
    // Twiddle factor ROM
    function automatic void get_twiddle(
        input int idx,
        output logic signed [DATA_WIDTH-1:0] tw_re, tw_im
    );
        case (idx & 31)
            0:  begin tw_re = 16'sh4000; tw_im = 16'sh0000; end
            1:  begin tw_re = 16'sh3FB1; tw_im = -16'sh0648; end
            2:  begin tw_re = 16'sh3EC5; tw_im = -16'sh0C8C; end
            3:  begin tw_re = 16'sh3D3F; tw_im = -16'sh12C8; end
            4:  begin tw_re = 16'sh3B21; tw_im = -16'sh18F9; end
            5:  begin tw_re = 16'sh3871; tw_im = -16'sh1F1A; end
            6:  begin tw_re = 16'sh3537; tw_im = -16'sh2528; end
            7:  begin tw_re = 16'sh3179; tw_im = -16'sh2B1F; end
            8:  begin tw_re = 16'sh2D41; tw_im = -16'sh30FC; end
            9:  begin tw_re = 16'sh2898; tw_im = -16'sh36BA; end
            10: begin tw_re = 16'sh2385; tw_im = -16'sh3C57; end
            11: begin tw_re = 16'sh1E0B; tw_im = -16'sh41CE; end
            12: begin tw_re = 16'sh1833; tw_im = -16'sh471D; end
            13: begin tw_re = 16'sh1205; tw_im = -16'sh4C40; end
            14: begin tw_re = 16'sh0B8E; tw_im = -16'sh5133; end
            15: begin tw_re = 16'sh04F5; tw_im = -16'sh55F6; end
            16: begin tw_re = 16'sh0000; tw_im = -16'sh5A82; end
            17: begin tw_re = -16'sh04F5; tw_im = -16'sh55F6; end
            18: begin tw_re = -16'sh0B8E; tw_im = -16'sh5133; end
            19: begin tw_re = -16'sh1205; tw_im = -16'sh4C40; end
            20: begin tw_re = -16'sh1833; tw_im = -16'sh471D; end
            21: begin tw_re = -16'sh1E0B; tw_im = -16'sh41CE; end
            22: begin tw_re = -16'sh2385; tw_im = -16'sh3C57; end
            23: begin tw_re = -16'sh2898; tw_im = -16'sh36BA; end
            24: begin tw_re = -16'sh2D41; tw_im = -16'sh30FC; end
            25: begin tw_re = -16'sh3179; tw_im = -16'sh2B1F; end
            26: begin tw_re = -16'sh3537; tw_im = -16'sh2528; end
            27: begin tw_re = -16'sh3871; tw_im = -16'sh1F1A; end
            28: begin tw_re = -16'sh3B21; tw_im = -16'sh18F9; end
            29: begin tw_re = -16'sh3D3F; tw_im = -16'sh12C8; end
            30: begin tw_re = -16'sh3EC5; tw_im = -16'sh0C8C; end
            31: begin tw_re = -16'sh3FB1; tw_im = -16'sh0648; end
            default: begin tw_re = 16'sh4000; tw_im = 16'sh0000; end
        endcase
    endfunction
    
    // Complex multiply (a + jb) * (c + jd) = (ac-bd) + j(ad+bc)
    function automatic void complex_mult(
        input logic signed [DATA_WIDTH-1:0] a_re, a_im, b_re, b_im,
        output logic signed [DATA_WIDTH-1:0] c_re, c_im
    );
        logic signed [31:0] temp_re, temp_im;
        temp_re = (a_re * b_re) - (a_im * b_im);
        temp_im = (a_re * b_im) + (a_im * b_re);
        // scale back down
        c_re = temp_re[29:14];
        c_im = temp_im[29:14];
    endfunction
    
    // Main FSM
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            ready <= 1'b1;
            input_count <= 5'd0;
            output_count <= 6'd0;
            stage_num <= 3'd0;
            compute_count <= 6'd0;
            
            for (int i = 0; i < FFT_SIZE; i++) begin
                data_real[i] <= 16'h0000;
                data_imag[i] <= 16'h0000;
                temp_real[i] <= 16'h0000;
                temp_imag[i] <= 16'h0000;
            end
            
        end else begin
            case (state)
                IDLE: begin
                    ready <= 1'b1;
                    if (valid_in) begin
                        // begin loading
                        data_real[bit_reverse(5'd0)] <= data_real_in;
                        data_imag[bit_reverse(5'd0)] <= data_imag_in;
                        input_count <= 5'd1;
                        ready <= 1'b0;
                        state <= LOAD_INPUT;
                    end
                end
                
                LOAD_INPUT: begin
                    if (valid_in) begin
                        data_real[bit_reverse(input_count)] <= data_real_in;
                        data_imag[bit_reverse(input_count)] <= data_imag_in;
                        
                        if (input_count == 5'd31) begin
                            input_count <= 5'd0;
                            stage_num <= 3'd0;
                            compute_count <= 6'd0;
                            state <= COMPUTE;
                        end else begin
                            input_count <= input_count + 1'b1;
                        end
                    end
                end
                
                COMPUTE: begin
                    int span, b, k, idx1, idx2, tw_idx;
                    logic signed [DATA_WIDTH-1:0] a_re, a_im, b_re, b_im;
                    logic signed [DATA_WIDTH-1:0] tw_re, tw_im, b_tw_re, b_tw_imag;
                    
                    span = 1 << stage_num;  // butterfly distance (1, 2, 4, 8, 16)
                    
                    // Pair selectoin:
                    // b = lower stage_num bits of compute_count
                    // k = upper bits of compute_count
                    // idx1 = (k * 2 * span) + b
                    // idx2 = idx1 + span
                    b = compute_count & (span - 1);           // lower bits for position within pair group
                    k = compute_count >> stage_num;            // upper bits for group number
                    idx1 = (k << (stage_num + 1)) | b;        // (k * 2 * span) + b
                    idx2 = idx1 + span;
                    tw_idx = b << (4 - stage_num);
                    
                    // load a and b
                    a_re = data_real[idx1];
                    a_im = data_imag[idx1];
                    b_re = data_real[idx2];
                    b_im = data_imag[idx2];
                    
                    // twiddle and multiply b * W
                    get_twiddle(tw_idx, tw_re, tw_im);
                    complex_mult(b_re, b_im, tw_re, tw_im, b_tw_re, b_tw_imag);
                    
                    // Butterfly with scaling to prevent overflow
                    temp_real[idx1] <= (a_re + b_tw_re) >>> 1;
                    temp_imag[idx1] <= (a_im + b_tw_imag) >>> 1;
                    temp_real[idx2] <= (a_re - b_tw_re) >>> 1;
                    temp_imag[idx2] <= (a_im - b_tw_imag) >>> 1;
                    
                    if (compute_count == 6'd15) begin  // 16 butterflies per stage
                        compute_count <= 6'd0;
                        // transition to SYNC to copy temp results
                        state <= SYNC;
                    end else begin
                        compute_count <= compute_count + 1'b1;
                    end
                end
                
                SYNC: begin
                    // wait 1 cycle for non-blocking temp assignments to settle, then copy
                    for (int i = 0; i < FFT_SIZE; i++) begin
                        data_real[i] <= temp_real[i];
                        data_imag[i] <= temp_imag[i];
                    end
                    
                    if (stage_num == 3'd4) begin
                        // need extra wait cycle before OUTPUT after completing stage 4
                        state <= FINAL_SYNC;
                    end else begin
                        stage_num <= stage_num + 1'b1;
                        state <= COMPUTE;
                    end
                end
                
                FINAL_SYNC: begin
                    // extra cycle to let final stage temp→data copy settle before OUTPUT
                    state <= OUTPUT;
                    output_count <= 6'd0;
                end
                
                OUTPUT: begin
                    // finished when counter reaches 32
                    if (output_count == 6'd0) begin
                        // verify data array on first output cycle
                        $display("[VERIFY] First OUTPUT cycle - data_real values:");
                        for (int i = 0; i < 32; i++) begin
                            $display("[VERIFY] data_real[%0d] = %h", i, data_real[i]);
                        end
                    end
                    
                    if (output_count == 6'd31) begin
                        // just output last bin, then go to IDLE
                        output_count <= 6'd0;
                        state <= IDLE;
                    end else begin
                        // output current bin, increment for next cycle
                        output_count <= output_count + 1'b1;
                    end
                end
            endcase
        end
    end
    
    // output assignments (natural order output - already bit-reversed due to DIT processing)
    // output_count tracks 0-32; read data_real/imag[output_count], stopping at 31
    assign data_real_out = data_real[output_count[4:0]];
    assign data_imag_out = data_imag[output_count[4:0]];
    assign valid_out = (state == OUTPUT) && (output_count < 6'd32);

endmodule

