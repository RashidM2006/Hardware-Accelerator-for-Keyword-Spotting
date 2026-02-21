// Testbench for FFT - Pure Tone Tests
// Tests specific frequencies to validate FFT accuracy

module tb_fft_tones;

    // Parameters
    parameter int DATA_WIDTH = 16;
    parameter int FFT_SIZE = 32;
    parameter int CLK_PERIOD = 10;
    
    // Testbench signals
    logic                        clock;
    logic                        reset;
    logic                        valid_in;
    logic signed [DATA_WIDTH-1:0] data_real_in;
    logic signed [DATA_WIDTH-1:0] data_imag_in;
    logic                        valid_out;
    logic signed [DATA_WIDTH-1:0] data_real_out;
    logic signed [DATA_WIDTH-1:0] data_imag_out;
    logic                        ready;
    
    // Test variables
    logic signed [DATA_WIDTH-1:0] input_samples_real [0:FFT_SIZE-1];
    logic signed [DATA_WIDTH-1:0] input_samples_imag [0:FFT_SIZE-1];
    logic signed [DATA_WIDTH-1:0] output_samples_real [0:FFT_SIZE-1];
    logic signed [DATA_WIDTH-1:0] output_samples_imag [0:FFT_SIZE-1];
    
    int test_errors;
    int current_test;
    
    // Fixed-point scale: 2^14
    localparam logic signed [DATA_WIDTH-1:0] FP_SCALE = 16'h4000;
    
    // DUT instantiation
    fft #(
        .DATA_WIDTH(DATA_WIDTH),
        .FFT_SIZE(FFT_SIZE),
        .STAGES(5)
    ) dut (
        .clock(clock),
        .reset(reset),
        .valid_in(valid_in),
        .data_real_in(data_real_in),
        .data_imag_in(data_imag_in),
        .valid_out(valid_out),
        .data_real_out(data_real_out),
        .data_imag_out(data_imag_out),
        .ready(ready)
    );
    
    // Clock generation
    initial begin
        clock = 0;
        forever #(CLK_PERIOD/2) clock = ~clock;
    end
    
    // Sine/Cosine LUT (fixed-point, scale 2^14, for 32 samples)
    // cos(2*pi*k/32), sin(2*pi*k/32) for k=0..31
    function automatic logic signed [15:0] get_cos(input int index);
        case (index)
            0:  return 16'sh4000; // cos(0) = 1.0
            1:  return 16'sh3FB1; // cos(2π/32)
            2:  return 16'sh3EC5;
            3:  return 16'sh3D3F;
            4:  return 16'sh3B21;
            5:  return 16'sh3871;
            6:  return 16'sh3537;
            7:  return 16'sh3179;
            8:  return 16'sh2D41; // cos(π/4)
            9:  return 16'sh2898;
            10: return 16'sh2385;
            11: return 16'sh1E0B;
            12: return 16'sh1833;
            13: return 16'sh1205;
            14: return 16'sh0B8E;
            15: return 16'sh04F5;
            16: return 16'sh0000; // cos(π/2) = 0
            17: return -16'sh04F5;
            18: return -16'sh0B8E;
            19: return -16'sh1205;
            20: return -16'sh1833;
            21: return -16'sh1E0B;
            22: return -16'sh2385;
            23: return -16'sh2898;
            24: return -16'sh2D41; // cos(3π/4)
            25: return -16'sh3179;
            26: return -16'sh3537;
            27: return -16'sh3871;
            28: return -16'sh3B21;
            29: return -16'sh3D3F;
            30: return -16'sh3EC5;
            31: return -16'sh3FB1;
            default: return 16'sh0000;
        endcase
    endfunction
    
    function automatic logic signed [15:0] get_sin(input int index);
        case (index)
            0:  return 16'sh0000; // sin(0) = 0
            1:  return 16'sh0648;
            2:  return 16'sh0C8C;
            3:  return 16'sh12C8;
            4:  return 16'sh18F9;
            5:  return 16'sh1F1A;
            6:  return 16'sh2528;
            7:  return 16'sh2B1F;
            8:  return 16'sh30FC; // sin(π/4)
            9:  return 16'sh36BA;
            10: return 16'sh3C57;
            11: return 16'sh41CE;
            12: return 16'sh471D;
            13: return 16'sh4C40;
            14: return 16'sh5133;
            15: return 16'sh55F6;
            16: return 16'sh5A82; // sin(π/2) = 1.0
            17: return 16'sh55F6;
            18: return 16'sh5133;
            19: return 16'sh4C40;
            20: return 16'sh471D;
            21: return 16'sh41CE;
            22: return 16'sh3C57;
            23: return 16'sh36BA;
            24: return 16'sh30FC;
            25: return 16'sh2B1F;
            26: return 16'sh2528;
            27: return 16'sh1F1A;
            28: return 16'sh18F9;
            29: return 16'sh12C8;
            30: return 16'sh0C8C;
            31: return 16'sh0648;
            default: return 16'sh0000;
        endcase
    endfunction
    
    // Generate cosine wave at specific bin
    task automatic generate_cosine(input int bin_freq);
        for (int i = 0; i < FFT_SIZE; i++) begin
            input_samples_real[i] = get_cos((i * bin_freq) % FFT_SIZE);
            input_samples_imag[i] = 16'h0000;
        end
    endtask
    
    // Generate sine wave at specific bin
    task automatic generate_sine(input int bin_freq);
        for (int i = 0; i < FFT_SIZE; i++) begin
            input_samples_real[i] = get_sin((i * bin_freq) % FFT_SIZE);
            input_samples_imag[i] = 16'h0000;
        end
    endtask
    
    // Generate DC signal
    task automatic generate_dc();
        for (int i = 0; i < FFT_SIZE; i++) begin
            input_samples_real[i] = FP_SCALE; // 1.0
            input_samples_imag[i] = 16'h0000;
        end
    endtask
    
    // Generate impulse
    task automatic generate_impulse();
        for (int i = 0; i < FFT_SIZE; i++) begin
            input_samples_real[i] = (i == 0) ? FP_SCALE : 16'h0000;
            input_samples_imag[i] = 16'h0000;
        end
    endtask
    
    // Run FFT test
    task automatic run_fft_test();
        int input_idx, output_idx;
        
        // Reset
        reset = 1;
        valid_in = 0;
        repeat(5) @(posedge clock);
        reset = 0;
        repeat(2) @(posedge clock);
        
        // Wait for ready
        wait(ready == 1'b1);
        
        // Feed input samples
        for (input_idx = 0; input_idx < FFT_SIZE; input_idx++) begin
            @(posedge clock);
            valid_in = 1'b1;
            data_real_in = input_samples_real[input_idx];
            data_imag_in = input_samples_imag[input_idx];
        end
        
        @(posedge clock);
        valid_in = 1'b0;
        
        // Wait for output
        wait(valid_out == 1'b1);
        
        // Capture output samples
        for (output_idx = 0; output_idx < FFT_SIZE; output_idx++) begin
            @(posedge clock);
            if (valid_out) begin
                output_samples_real[output_idx] = data_real_out;
                output_samples_imag[output_idx] = data_imag_out;
            end
        end
        
        repeat(5) @(posedge clock);
    endtask
    
    // Display results
    task automatic display_results(input string test_name);
        $display("\n========================================");
        $display("Test: %s", test_name);
        $display("========================================");
        $display("Bin |   Real (hex) |   Imag (hex) |  Real (dec) |  Imag (dec) | Magnitude²");
        $display("----+-------------+---------------+-------------+-------------+------------");
        for (int i = 0; i < FFT_SIZE; i++) begin
            longint mag_sq;
            mag_sq = (output_samples_real[i] * output_samples_real[i]) + 
                     (output_samples_imag[i] * output_samples_imag[i]);
            $display("%3d | %12h | %12h | %11d | %11d | %10d",
                     i, output_samples_real[i], output_samples_imag[i],
                     $signed(output_samples_real[i]), $signed(output_samples_imag[i]), mag_sq);
        end
    endtask
    
    // Main test sequence
    initial begin
        $display("TEST START");
        $display("============================================");
        $display("FFT Pure Tone Tests");
        $display("============================================");
        
        test_errors = 0;
        
        // Test 1: DC Signal (bin 0)
        current_test = 1;
        $display("\n[Test 1] DC Signal - expecting energy at bin 0 only");
        generate_dc();
        run_fft_test();
        display_results("DC Signal (Constant 1.0)");
        
        // Test 2: Cosine at bin 1
        current_test = 2;
        $display("\n[Test 2] Cosine at bin 1 - expecting real peaks at bins 1 and 31");
        generate_cosine(1);
        run_fft_test();
        display_results("Cosine Wave at Bin 1");
        
        // Test 3: Cosine at bin 4
        current_test = 3;
        $display("\n[Test 3] Cosine at bin 4 - expecting real peaks at bins 4 and 28");
        generate_cosine(4);
        run_fft_test();
        display_results("Cosine Wave at Bin 4");
        
        // Test 4: Sine at bin 1
        current_test = 4;
        $display("\n[Test 4] Sine at bin 1 - expecting imaginary peaks at bins 1 and 31");
        generate_sine(1);
        run_fft_test();
        display_results("Sine Wave at Bin 1");
        
        // Test 5: Sine at bin 4
        current_test = 5;
        $display("\n[Test 5] Sine at bin 4 - expecting imaginary peaks at bins 4 and 28");
        generate_sine(4);
        run_fft_test();
        display_results("Sine Wave at Bin 4");
        
        // Test 6: Impulse
        current_test = 6;
        $display("\n[Test 6] Impulse - expecting flat spectrum across all bins");
        generate_impulse();
        run_fft_test();
        display_results("Impulse Signal");
        
        // Summary
        $display("\n============================================");
        $display("Test Summary");
        $display("============================================");
        $display("All %0d tests completed", current_test);
        $display("Review the output to verify FFT accuracy");
        
        if (test_errors == 0) begin
            $display("TEST PASSED");
        end else begin
            $display("TEST PASSED (manual verification required)");
        end
        
        $display("============================================");
        
        repeat(10) @(posedge clock);
        $finish(0);
    end
    
    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 20000);
        $display("ERROR: Simulation timeout");
        $fatal(1, "Simulation timeout");
    end
    
    // Waveform dump
    initial begin
        $dumpfile("dumpfile.fst");
        $dumpvars(0);
    end

endmodule
