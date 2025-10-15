`timescale 1ns / 1ps

// =============================================================================
// Testbench for Distance Calculation Module
// =============================================================================
module tb_distance_calculation;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter DATA_WIDTH = 16;
    parameter NUM_FEATURES = 4;
    parameter ADDR_WIDTH = 8;
    parameter CLK_PERIOD = 10;
    
    // =========================================================================
    // DUT Signals
    // =========================================================================
    reg clk;
    reg rst_n;
    
    // Control signals
    reg calculate_distance;
    wire distance_done;
    
    // Test sample feature input (streamed)
    reg [DATA_WIDTH-1:0] test_feature;
    reg test_feature_valid;
    
    // Memory interface for stored samples (read-only)
    wire [ADDR_WIDTH-1:0] sample_feature_addr;
    reg [DATA_WIDTH-1:0] sample_feature_data;
    
    // Distance output
    wire [2*DATA_WIDTH-1:0] calculated_distance;
    
    // Control
    reg en_dist_calc;
    wire distance_valid;
    
    // =========================================================================
    // Test Data Storage
    // =========================================================================
    // Test samples
    reg [DATA_WIDTH-1:0] test_sample [0:NUM_FEATURES-1];
    
    // Stored training samples
    reg [DATA_WIDTH-1:0] training_samples [0:9][0:NUM_FEATURES-1];  // 10 samples
    
    // Expected distances
    reg [2*DATA_WIDTH-1:0] expected_distances [0:9];
    
    // Simulation memory to model sample feature memory
    reg [DATA_WIDTH-1:0] sample_memory [0:255];
    
    // =========================================================================
    // FSM State Monitoring
    // =========================================================================
    wire [2:0] current_state;
    assign current_state = dut.state;
    
    reg [200:0] state_name;
    always @(*) begin
        case (current_state)
            3'd0: state_name = "IDLE";
            3'd1: state_name = "LOAD_TEST_SAMPLE";
            3'd2: state_name = "LOAD_SAMPLE_ADDR";
            3'd3: state_name = "WAIT_SAMPLE";
            3'd4: state_name = "CALCULATE_DISTANCE";
            3'd5: state_name = "STORE_DISTANCE";
            default: state_name = "UNKNOWN";
        endcase
    end
    
    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // =========================================================================
    // Memory Read Model (Synchronous)
    // =========================================================================
    always @(posedge clk) begin
        sample_feature_data <= sample_memory[sample_feature_addr];
    end
    
    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    distance_calculation #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_FEATURES(NUM_FEATURES),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        
        .calculate_distance(calculate_distance),
        .distance_done(distance_done),
        
        .test_feature(test_feature),
        .test_feature_valid(test_feature_valid),
        
        .sample_feature_addr(sample_feature_addr),
        .sample_feature_data(sample_feature_data),
        
        .calculated_distance(calculated_distance),
        
        .en_dist_calc(en_dist_calc),
        .distance_valid(distance_valid)
    );
    
    // =========================================================================
    // Test Statistics
    // =========================================================================
    integer test_count;
    integer pass_count;
    integer fail_count;
    
    // =========================================================================
    // Helper Tasks
    // =========================================================================
    
    // Reset task
    task reset_system;
        begin
            $display("\n[%0t] === Performing System Reset ===", $time);
            rst_n = 0;
            calculate_distance = 0;
            test_feature = 0;
            test_feature_valid = 0;
            en_dist_calc = 0;
            
            repeat(5) @(posedge clk);
            rst_n = 1;
            repeat(2) @(posedge clk);
            
            $display("[%0t] Reset complete - State: %s", $time, state_name);
        end
    endtask
    
    // Initialize test data
    task init_test_data;
        integer i, j, addr;
        begin
            $display("\n[%0t] Initializing test data...", $time);
            
            // Test sample: [10, 20, 30, 40]
            test_sample[0] = 16'd10;
            test_sample[1] = 16'd20;
            test_sample[2] = 16'd30;
            test_sample[3] = 16'd40;
            
            $display("  Test Sample: [%0d, %0d, %0d, %0d]", 
                     test_sample[0], test_sample[1], test_sample[2], test_sample[3]);
            
            // Training sample 0: [10, 20, 30, 40] - Identical (distance = 0)
            training_samples[0][0] = 16'd10;
            training_samples[0][1] = 16'd20;
            training_samples[0][2] = 16'd30;
            training_samples[0][3] = 16'd40;
            expected_distances[0] = 32'd0;
            
            // Training sample 1: [11, 21, 31, 41] - Distance = 4 (each diff = 1, sum = 4*1 = 4)
            training_samples[1][0] = 16'd11;
            training_samples[1][1] = 16'd21;
            training_samples[1][2] = 16'd31;
            training_samples[1][3] = 16'd41;
            expected_distances[1] = 32'd4;  // (1^2 + 1^2 + 1^2 + 1^2)
            
            // Training sample 2: [12, 22, 32, 42] - Distance = 16
            training_samples[2][0] = 16'd12;
            training_samples[2][1] = 16'd22;
            training_samples[2][2] = 16'd32;
            training_samples[2][3] = 16'd42;
            expected_distances[2] = 32'd16;  // (2^2 + 2^2 + 2^2 + 2^2)
            
            // Training sample 3: [15, 25, 35, 45] - Distance = 100
            training_samples[3][0] = 16'd15;
            training_samples[3][1] = 16'd25;
            training_samples[3][2] = 16'd35;
            training_samples[3][3] = 16'd45;
            expected_distances[3] = 32'd100;  // (5^2 + 5^2 + 5^2 + 5^2)
            
            // Training sample 4: [20, 30, 40, 50] - Distance = 400
            training_samples[4][0] = 16'd20;
            training_samples[4][1] = 16'd30;
            training_samples[4][2] = 16'd40;
            training_samples[4][3] = 16'd50;
            expected_distances[4] = 32'd400;  // (10^2 + 10^2 + 10^2 + 10^2)
            
            // Training sample 5: [0, 0, 0, 0] - All zeros
            training_samples[5][0] = 16'd0;
            training_samples[5][1] = 16'd0;
            training_samples[5][2] = 16'd0;
            training_samples[5][3] = 16'd0;
            expected_distances[5] = 32'd3000;  // (10^2 + 20^2 + 30^2 + 40^2)
            
            // Training sample 6: [100, 100, 100, 100] - Large values
            training_samples[6][0] = 16'd100;
            training_samples[6][1] = 16'd100;
            training_samples[6][2] = 16'd100;
            training_samples[6][3] = 16'd100;
            expected_distances[6] = 32'd32400;  // (90^2 + 80^2 + 70^2 + 60^2)
            
            // Training sample 7: [9, 19, 29, 39] - Very close
            training_samples[7][0] = 16'd9;
            training_samples[7][1] = 16'd19;
            training_samples[7][2] = 16'd29;
            training_samples[7][3] = 16'd39;
            expected_distances[7] = 32'd4;  // (1^2 + 1^2 + 1^2 + 1^2)
            
            // Training sample 8: [13, 17, 33, 37] - Mixed differences
            training_samples[8][0] = 16'd13;
            training_samples[8][1] = 16'd17;
            training_samples[8][2] = 16'd33;
            training_samples[8][3] = 16'd37;
            expected_distances[8] = 32'd27;  // (3^2 + 3^2 + 3^2 + 3^2) = 36? Let me recalc: (3^2 + (-3)^2 + 3^2 + (-3)^2) = 9+9+9+9=36
            expected_distances[8] = 32'd36;  // Corrected
            
            // Training sample 9: Negative differences test
            training_samples[9][0] = 16'd5;
            training_samples[9][1] = 16'd10;
            training_samples[9][2] = 16'd15;
            training_samples[9][3] = 16'd20;
            expected_distances[9] = 32'd500;  // (5^2 + 10^2 + 15^2 + 20^2) = 25+100+225+400
            
            // Load training samples into memory
            for (i = 0; i < 10; i = i + 1) begin
                for (j = 0; j < NUM_FEATURES; j = j + 1) begin
                    addr = (i * NUM_FEATURES) + j;
                    sample_memory[addr] = training_samples[i][j];
                end
                $display("  Training[%0d]: [%0d, %0d, %0d, %0d] -> Expected Distance: %0d",
                         i, training_samples[i][0], training_samples[i][1], 
                         training_samples[i][2], training_samples[i][3],
                         expected_distances[i]);
            end
        end
    endtask
    
    // Stream test features into module
    task load_test_features;
        integer i;
        begin
            $display("\n[%0t] Loading test features...", $time);
            for (i = 0; i < NUM_FEATURES; i = i + 1) begin
                @(posedge clk);
                test_feature = test_sample[i];
                test_feature_valid = 1;
                $display("[%0t]   Loading feature[%0d] = %0d", $time, i, test_feature);
            end
            @(posedge clk);
            test_feature_valid = 0;
            $display("[%0t] Test features loaded", $time);
        end
    endtask
    
    // Calculate distance for a specific training sample
    task calculate_sample_distance;
        input integer sample_idx;
        reg [2*DATA_WIDTH-1:0] result;
        real error_percent;
        begin
            $display("\n[%0t] === Calculating distance for Sample %0d ===", $time, sample_idx);
            $display("  Sample: [%0d, %0d, %0d, %0d]", 
                     training_samples[sample_idx][0], training_samples[sample_idx][1],
                     training_samples[sample_idx][2], training_samples[sample_idx][3]);
            $display("  Expected Distance: %0d", expected_distances[sample_idx]);
            
            // Start calculation
            @(posedge clk);
            en_dist_calc = 1;
            calculate_distance = 1;
            @(posedge clk);
            calculate_distance = 0;
            
            // Wait for completion
            $display("[%0t] Waiting for distance_done...", $time);
            wait(distance_done);
            @(posedge clk);
            
            result = calculated_distance;
            $display("[%0t] Calculation complete!", $time);
            $display("  Calculated Distance: %0d", result);
            $display("  Expected Distance:   %0d", expected_distances[sample_idx]);
            
            // Verify result
            test_count = test_count + 1;
            if (result === expected_distances[sample_idx]) begin
                $display("  ✓ PASS: Distance matches exactly");
                pass_count = pass_count + 1;
            end else begin
                error_percent = ((result - expected_distances[sample_idx]) * 100.0) / expected_distances[sample_idx];
                $display("  ✗ FAIL: Distance mismatch (error: %.2f%%)", error_percent);
                fail_count = fail_count + 1;
            end
            
            en_dist_calc = 0;
            repeat(2) @(posedge clk);
        end
    endtask
    
    // Test state transitions
    task test_fsm_states;
        begin
            $display("\n[%0t] === Testing FSM State Transitions ===", $time);
            
            test_count = test_count + 1;
            if (current_state == 3'd0) begin  // IDLE
                $display("[%0t] ✓ PASS: Started in IDLE state", $time);
                pass_count = pass_count + 1;
            end else begin
                $display("[%0t] ✗ FAIL: Not in IDLE state", $time);
                fail_count = fail_count + 1;
            end
            
            // Start calculation without loading test features (error case)
            @(posedge clk);
            en_dist_calc = 1;
            calculate_distance = 1;
            @(posedge clk);
            calculate_distance = 0;
            
            @(posedge clk);
            test_count = test_count + 1;
            if (current_state == 3'd1) begin  // LOAD_TEST_SAMPLE
                $display("[%0t] ✓ PASS: Transitioned to LOAD_TEST_SAMPLE", $time);
                pass_count = pass_count + 1;
            end else begin
                $display("[%0t] ✗ FAIL: Did not transition to LOAD_TEST_SAMPLE", $time);
                fail_count = fail_count + 1;
            end
            
            en_dist_calc = 0;
            repeat(5) @(posedge clk);
        end
    endtask
    
    // =========================================================================
    // Timeout Watchdog
    // =========================================================================
    initial begin
        #500000;  // 500us timeout
        $display("\n[ERROR] Simulation timeout!");
        $display("Last state: %s", state_name);
        $finish;
    end
    
    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        $display("\n");
        $display("========================================");
        $display("Distance Calculation Testbench");
        $display("========================================");
        $display("Configuration:");
        $display("  DATA_WIDTH   = %0d", DATA_WIDTH);
        $display("  NUM_FEATURES = %0d", NUM_FEATURES);
        $display("  ADDR_WIDTH   = %0d", ADDR_WIDTH);
        $display("========================================\n");
        
        // =====================================================================
        // Test 1: Reset and Initial State
        // =====================================================================
        $display("\n========================================");
        $display("Test 1: Reset and Initial State");
        $display("========================================");
        
        reset_system();
        init_test_data();
        
        test_count = test_count + 1;
        if (current_state == 3'd0) begin
            $display("✓ PASS: In IDLE state after reset");
            pass_count = pass_count + 1;
        end else begin
            $display("✗ FAIL: Not in IDLE state after reset");
            fail_count = fail_count + 1;
        end
        
        // =====================================================================
        // Test 2: FSM State Transitions
        // =====================================================================
        $display("\n========================================");
        $display("Test 2: FSM State Transitions");
        $display("========================================");
        
        test_fsm_states();
        reset_system();
        
        // =====================================================================
        // Test 3: Distance Calculation - Identical Samples (Distance = 0)
        // =====================================================================
        $display("\n========================================");
        $display("Test 3: Identical Samples (Distance = 0)");
        $display("========================================");
        
        load_test_features();
        calculate_sample_distance(0);
        
        // =====================================================================
        // Test 4: Small Distance
        // =====================================================================
        $display("\n========================================");
        $display("Test 4: Small Distance");
        $display("========================================");
        
        reset_system();
        load_test_features();
        calculate_sample_distance(1);
        
        // =====================================================================
        // Test 5: Medium Distance
        // =====================================================================
        $display("\n========================================");
        $display("Test 5: Medium Distance");
        $display("========================================");
        
        reset_system();
        load_test_features();
        calculate_sample_distance(3);
        
        // =====================================================================
        // Test 6: Large Distance
        // =====================================================================
        $display("\n========================================");
        $display("Test 6: Large Distance");
        $display("========================================");
        
        reset_system();
        load_test_features();
        calculate_sample_distance(4);
        
        // =====================================================================
        // Test 7: All Zeros Sample
        // =====================================================================
        $display("\n========================================");
        $display("Test 7: All Zeros Sample");
        $display("========================================");
        
        reset_system();
        load_test_features();
        calculate_sample_distance(5);
        
        // =====================================================================
        // Test 8: Large Values
        // =====================================================================
        $display("\n========================================");
        $display("Test 8: Large Values");
        $display("========================================");
        
        reset_system();
        load_test_features();
        calculate_sample_distance(6);
        
        // =====================================================================
        // Test 9: Very Close Values
        // =====================================================================
        $display("\n========================================");
        $display("Test 9: Very Close Values");
        $display("========================================");
        
        reset_system();
        load_test_features();
        calculate_sample_distance(7);
        
        // =====================================================================
        // Test 10: Multiple Sequential Calculations
        // =====================================================================
        $display("\n========================================");
        $display("Test 10: Multiple Sequential Calculations");
        $display("========================================");
        
        reset_system();
        load_test_features();
        
        // Calculate distances for multiple samples in sequence
        for (integer i = 0; i < 5; i = i + 1) begin
            calculate_sample_distance(i);
        end
        
        // =====================================================================
        // Test 11: Signed Arithmetic Test
        // =====================================================================
        $display("\n========================================");
        $display("Test 11: Signed Arithmetic (Negative Differences)");
        $display("========================================");
        
        reset_system();
        load_test_features();
        calculate_sample_distance(9);
        
        // =====================================================================
        // Final Report
        // =====================================================================
        repeat(10) @(posedge clk);
        
        $display("\n========================================");
        $display("Test Complete!");
        $display("========================================");
        $display("Test Statistics:");
        $display("  Total Tests: %0d", test_count);
        $display("  Passed:      %0d (%.1f%%)", pass_count, (pass_count * 100.0) / test_count);
        $display("  Failed:      %0d (%.1f%%)", fail_count, (fail_count * 100.0) / test_count);
        $display("========================================\n");
        
        if (fail_count == 0)
            $display("✓ All tests PASSED!");
        else
            $display("✗ Some tests FAILED!");
        
        $finish;
    end
    
    // =========================================================================
    // State Transition Monitor
    // =========================================================================
    reg [2:0] prev_state;
    initial prev_state = 3'd0;
    
    always @(posedge clk) begin
        if (current_state !== prev_state) begin
            $display("[%0t] State: %s -> %s", $time, 
                     get_state_name(prev_state), state_name);
            prev_state = current_state;
        end
    end
    
    function [200:0] get_state_name;
        input [2:0] state;
        begin
            case (state)
                3'd0: get_state_name = "IDLE";
                3'd1: get_state_name = "LOAD_TEST_SAMPLE";
                3'd2: get_state_name = "LOAD_SAMPLE_ADDR";
                3'd3: get_state_name = "WAIT_SAMPLE";
                3'd4: get_state_name = "CALCULATE_DISTANCE";
                3'd5: get_state_name = "STORE_DISTANCE";
                default: get_state_name = "UNKNOWN";
            endcase
        end
    endfunction
    
    // =========================================================================
    // Waveform Dump
    // =========================================================================
    initial begin
        $dumpfile("distance_calculation.vcd");
        $dumpvars(0, tb_distance_calculation);
    end

endmodule
