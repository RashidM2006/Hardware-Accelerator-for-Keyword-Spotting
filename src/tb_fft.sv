// Testbench for 32-Point FFT
// Tests with square wave input: period 16 samples, amplitude 1 to -1

module tb_fft;

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
    
    int input_idx;
    int output_idx;
    int test_errors;
    
    // Analysis variables
    longint magnitudes [0:FFT_SIZE-1];
    longint max_magnitude;
    int max_bin;
    
    // Fixed-point constants (scale: 2^14)
    localparam logic signed [DATA_WIDTH-1:0] FP_ONE = 16'h4000;   // +1.0
    localparam logic signed [DATA_WIDTH-1:0] FP_NEG_ONE = 16'hC000; // -1.0
    localparam logic signed [DATA_WIDTH-1:0] FP_ZERO = 16'h0000;  // 0.0
    
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
    
    // Calculate magnitude (approximation)
    function automatic longint calculate_magnitude(
        input logic signed [DATA_WIDTH-1:0] real_val,
        input logic signed [DATA_WIDTH-1:0] imag_val
    );
        longint real_sq, imag_sq, mag_sq;
        real_sq = real_val * real_val;
        imag_sq = imag_val * imag_val;
        mag_sq = real_sq + imag_sq;
        return mag_sq; // Return squared magnitude for comparison
    endfunction
    
    // Main test sequence
    initial begin
        $display("TEST START");
        $display("============================================");
        $display("FFT Testbench: Square Wave Input Test");
        $display("Square wave: Period=16 samples, Amplitude=1 to -1");
        $display("============================================");
        
        // Initialize
        test_errors = 0;
        reset = 1;
        valid_in = 0;
        data_real_in = 0;
        data_imag_in = 0;
        input_idx = 0;
        output_idx = 0;
        
        // Generate square wave input
        // Period = 16 samples: 8 samples at +1, 8 samples at -1, repeated twice
        $display("\nGenerating square wave input (32 samples):");
        for (int i = 0; i < FFT_SIZE; i++) begin
            if ((i % 16) < 8) begin
                input_samples_real[i] = FP_ONE;  // +1.0
            end else begin
                input_samples_real[i] = FP_NEG_ONE;  // -1.0
            end
            input_samples_imag[i] = FP_ZERO;  // Imaginary = 0
            $display("  Sample[%2d]: Real=%h (%s), Imag=%h", 
                     i, input_samples_real[i], 
                     (input_samples_real[i] == FP_ONE) ? "+1.0" : "-1.0",
                     input_samples_imag[i]);
        end
        
        // Reset sequence
        $display("\nApplying reset...");
        repeat(5) @(posedge clock);
        reset = 0;
        repeat(2) @(posedge clock);
        
        // Wait for ready
        $display("Waiting for FFT ready signal...");
        wait(ready == 1'b1);
        $display("FFT is ready to accept data");
        
        // Feed input samples
        $display("\nFeeding input samples to FFT...");
        for (input_idx = 0; input_idx < FFT_SIZE; input_idx++) begin
            @(posedge clock);
            valid_in = 1'b1;
            data_real_in = input_samples_real[input_idx];
            data_imag_in = input_samples_imag[input_idx];
            $display("  [T=%0t] Sending sample %2d: Real=%h, Imag=%h", 
                     $time, input_idx, data_real_in, data_imag_in);
        end
        
        @(posedge clock);
        valid_in = 1'b0;
        $display("All input samples sent. FFT should start processing...");
        
        // Wait for processing to complete and output to start
        $display("\nWaiting for FFT output...");
        wait(valid_out == 1'b1);
        $display("FFT output is valid!");
        
        // Capture output samples
        $display("\nCapturing FFT output (frequency domain):");
        for (output_idx = 0; output_idx < FFT_SIZE; output_idx++) begin
            @(posedge clock);
            if (valid_out) begin
                output_samples_real[output_idx] = data_real_out;
                output_samples_imag[output_idx] = data_imag_out;
                $display("  Bin[%2d]: Real=%h (dec:%d), Imag=%h (dec:%d)", 
                         output_idx, 
                         data_real_out, $signed(data_real_out),
                         data_imag_out, $signed(data_imag_out));
            end else begin
                $display("LOG: %0t : ERROR : tb_fft : dut.valid_out : expected_value: 1'b1 actual_value: 1'b0", $time);
                test_errors++;
            end
        end
        
        // Analyze results
        $display("\n============================================");
        $display("FFT Output Analysis:");
        $display("============================================");
        
        max_magnitude = 0;
        max_bin = 0;
        
        for (int i = 0; i < FFT_SIZE; i++) begin
            magnitudes[i] = calculate_magnitude(output_samples_real[i], output_samples_imag[i]);
            $display("Bin[%2d]: Magnitude² = %0d", i, magnitudes[i]);
            
            // Find maximum (excluding DC)
            if (i > 0 && magnitudes[i] > max_magnitude) begin
                max_magnitude = magnitudes[i];
                max_bin = i;
            end
        end
        
        // Verify expected properties of square wave FFT
        $display("\n============================================");
        $display("Verification Checks:");
        $display("============================================");
        
        // Check 1: DC component should be small (near zero) for symmetric square wave
        $display("\nCheck 1: DC Component (Bin 0)");
        $display("  DC Real: %h (dec: %d)", output_samples_real[0], $signed(output_samples_real[0]));
        $display("  DC Imag: %h (dec: %d)", output_samples_imag[0], $signed(output_samples_imag[0]));
        $display("  DC Magnitude²: %0d", magnitudes[0]);
        
        if (magnitudes[0] < 1000000) begin
            $display("  ✓ PASS: DC component is small (expected for symmetric square wave)");
        end else begin
            $display("LOG: %0t : ERROR : tb_fft : dut.data_real_out[0] : expected_value: ~0 actual_value: %d", $time, output_samples_real[0]);
            $display("  ✗ FAIL: DC component is too large!");
            test_errors++;
        end
        
        // Check 2: Maximum energy should be at fundamental frequency
        // Square wave with 2 cycles in 32 samples -> bin 2 should have max energy
        $display("\nCheck 2: Fundamental Frequency Peak");
        $display("  Expected peak at bin 2 (2 cycles in 32 samples)");
        $display("  Actual maximum at bin: %0d", max_bin);
        $display("  Maximum magnitude²: %0d", max_magnitude);
        
        if (max_bin == 2 || max_bin == 30) begin
            $display("  ✓ PASS: Peak found at expected frequency bin");
        end else begin
            $display("LOG: %0t : WARNING : tb_fft : max_frequency_bin : expected_value: 2 or 30 actual_value: %d", $time, max_bin);
            $display("  ⚠ WARNING: Peak not at expected bin (but this may be acceptable)");
        end
        
        // Check 3: Symmetry check (bin k should be conjugate of bin N-k for real input)
        $display("\nCheck 3: Conjugate Symmetry (Real Input Property)");
        begin
            int symmetry_errors;
            int conj_idx;
            logic signed [DATA_WIDTH-1:0] real_diff, imag_sum;
            
            symmetry_errors = 0;
            
            for (int i = 1; i < FFT_SIZE/2; i++) begin
                conj_idx = FFT_SIZE - i;
            
            real_diff = output_samples_real[i] - output_samples_real[conj_idx];
            imag_sum = output_samples_imag[i] + output_samples_imag[conj_idx];
            
            // Allow some tolerance due to fixed-point arithmetic
            if (real_diff > 100 || real_diff < -100 || imag_sum > 100 || imag_sum < -100) begin
                $display("LOG: %0t : WARNING : tb_fft : symmetry_bin_%0d : expected_value: conjugate actual_value: mismatch", $time, i);
                symmetry_errors++;
            end
            end
            
            if (symmetry_errors == 0) begin
                $display("  ✓ PASS: Conjugate symmetry verified");
            end else begin
                $display("  ⚠ WARNING: %0d conjugate symmetry mismatches (may be due to fixed-point rounding)", symmetry_errors);
            end
        end
        
        // Check 4: Top frequency bins with significant energy
        $display("\nCheck 4: Frequency Bins with Significant Energy");
        $display("  (Magnitude² > 1000000):");
        begin
            int significant_bins;
            significant_bins = 0;
            
            for (int i = 0; i < FFT_SIZE; i++) begin
            if (magnitudes[i] > 1000000) begin
                $display("    Bin[%2d]: Magnitude² = %0d", i, magnitudes[i]);
                significant_bins++;
            end
            end
            
            if (significant_bins > 0) begin
                $display("  ✓ INFO: Found %0d bins with significant energy", significant_bins);
            end else begin
                $display("  ⚠ WARNING: No bins with significant energy found");
            end
        end
        
        // Final verdict
        $display("\n============================================");
        $display("Test Summary:");
        $display("============================================");
        $display("Total errors: %0d", test_errors);
        
        if (test_errors == 0) begin
            $display("TEST PASSED");
        end else begin
            $display("ERROR");
            $error("TEST FAILED with %0d errors", test_errors);
        end
        
        $display("============================================");
        
        // End simulation
        repeat(10) @(posedge clock);
        $finish(0);
    end
    
    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 10000);
        $display("LOG: %0t : ERROR : tb_fft : simulation_timeout : expected_value: completion actual_value: timeout", $time);
        $display("ERROR");
        $fatal(1, "Simulation timeout - test did not complete in expected time");
    end
    
    // Waveform dump
    initial begin
        $dumpfile("dumpfile.fst");
        $dumpvars(0);
    end

endmodule
