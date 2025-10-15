`timescale 1ns / 1ps

// =============================================================================
// Testbench for KNN Control Unit
// =============================================================================
module tb_knn_control_unit;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter NUM_SAMPLES = 8;
    parameter NUM_FEATURES = 4;
    parameter K = 3;
    parameter ADDR_WIDTH = 8;
    parameter CLK_PERIOD = 10;
    
    // =========================================================================
    // DUT Signals
    // =========================================================================
    reg clk;
    reg rst_n;
    
    // External control inputs
    reg start_classify;
    reg [ADDR_WIDTH-1:0] k_value;
    reg [ADDR_WIDTH-1:0] num_samples;
    reg [$clog2(NUM_FEATURES)-1:0] num_features;
    
    // Status inputs from datapath modules
    reg distance_done;
    reg sort_done;
    reg majority_done;
    reg test_sample_loaded;
    
    // Control outputs to memory
    wire sample_ren;
    wire [ADDR_WIDTH-1:0] sample_raddr;
    wire label_ren;
    wire [ADDR_WIDTH-1:0] label_raddr;
    wire test_ren;
    wire [$clog2(NUM_FEATURES)-1:0] test_raddr;
    wire kbest_ren;
    wire [$clog2(NUM_SAMPLES)-1:0] kbest_raddr;
    
    // Control outputs to distance calculation
    wire calculate_distance;
    wire en_dist_calc;
    wire load_test_sample;
    
    // Control outputs to sort
    wire sort_start;
    wire sort_clear;
    wire en_sort;
    
    // Control outputs to majority voting
    wire majority_start;
    wire en_majority_labeling;
    
    // Status outputs
    wire classification_done;
    wire [ADDR_WIDTH-1:0] current_sample_idx;
    wire [$clog2(NUM_FEATURES)-1:0] current_feature_idx;
    wire busy;
    
    // =========================================================================
    // FSM State Monitoring (for debug)
    // =========================================================================
    wire [3:0] current_state;
    assign current_state = dut.state;
    
    // State names for display
    reg [200:0] state_name;
    always @(*) begin
        case (current_state)
            4'd0:  state_name = "IDLE";
            4'd1:  state_name = "LOAD_TEST_SAMPLE";
            4'd2:  state_name = "STORE_SAMPLE_LABELS";
            4'd3:  state_name = "STORE_SAMPLES";
            4'd4:  state_name = "LOAD_SAMPLE_FEATURES";
            4'd5:  state_name = "CALCULATE_DISTANCE";
            4'd6:  state_name = "STORE_DISTANCE";
            4'd7:  state_name = "SORT_K_NEAREST";
            4'd8:  state_name = "LOAD_FEATURES";
            4'd9:  state_name = "MAJORITY_LABELING";
            4'd10: state_name = "STORE_TEST_SAMPLE";
            4'd11: state_name = "OUTPUT_LABEL";
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
    // DUT Instantiation
    // =========================================================================
    knn_control_unit #(
        .NUM_SAMPLES(NUM_SAMPLES),
        .NUM_FEATURES(NUM_FEATURES),
        .K(K),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        
        // External control
        .start_classify(start_classify),
        .k_value(k_value),
        .num_samples(num_samples),
        .num_features(num_features),
        
        // Status inputs
        .distance_done(distance_done),
        .sort_done(sort_done),
        .majority_done(majority_done),
        .test_sample_loaded(test_sample_loaded),
        
        // Memory controls
        .sample_ren(sample_ren),
        .sample_raddr(sample_raddr),
        .label_ren(label_ren),
        .label_raddr(label_raddr),
        .test_ren(test_ren),
        .test_raddr(test_raddr),
        .kbest_ren(kbest_ren),
        .kbest_raddr(kbest_raddr),
        
        // Distance calculation controls
        .calculate_distance(calculate_distance),
        .en_dist_calc(en_dist_calc),
        .load_test_sample(load_test_sample),
        
        // Sort controls
        .sort_start(sort_start),
        .sort_clear(sort_clear),
        .en_sort(en_sort),
        
        // Majority voting controls
        .majority_start(majority_start),
        .en_majority_labeling(en_majority_labeling),
        
        // Status outputs
        .classification_done(classification_done),
        .current_sample_idx(current_sample_idx),
        .current_feature_idx(current_feature_idx),
        .busy(busy)
    );
    
    // =========================================================================
    // Test Statistics
    // =========================================================================
    integer test_count;
    integer pass_count;
    integer fail_count;
    integer error_count;
    
    // State transition tracking
    reg [3:0] prev_state;
    integer state_change_count;
    
    // =========================================================================
    // Helper Tasks
    // =========================================================================
    
    // Reset task
    task reset_system;
        begin
            $display("\n[%0t] === Performing System Reset ===", $time);
            rst_n = 0;
            start_classify = 0;
            k_value = K;
            num_samples = NUM_SAMPLES;
            num_features = NUM_FEATURES;
            distance_done = 0;
            sort_done = 0;
            majority_done = 0;
            test_sample_loaded = 0;
            
            repeat(5) @(posedge clk);
            rst_n = 1;
            repeat(2) @(posedge clk);
            
            $display("[%0t] Reset complete - State: %s", $time, state_name);
        end
    endtask
    
    // Check if FSM is in expected state
    task check_state;
        input [3:0] expected_state;
        input [200:0] test_description;
        begin
            test_count = test_count + 1;
            if (current_state === expected_state) begin
                $display("[%0t] ✓ PASS: %s - State = %s", $time, test_description, state_name);
                pass_count = pass_count + 1;
            end else begin
                $display("[%0t] ✗ FAIL: %s - Expected state %0d, got %0d (%s)", 
                         $time, test_description, expected_state, current_state, state_name);
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    // Check if signal has expected value
    task check_signal;
        input signal_value;
        input expected_value;
        input [200:0] signal_name;
        begin
            test_count = test_count + 1;
            if (signal_value === expected_value) begin
                $display("[%0t] ✓ PASS: %s = %b", $time, signal_name, signal_value);
                pass_count = pass_count + 1;
            end else begin
                $display("[%0t] ✗ FAIL: %s = %b (expected %b)", 
                         $time, signal_name, signal_value, expected_value);
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    // Simulate distance calculation completion
    task simulate_distance_calc;
        input integer cycles;
        begin
            $display("[%0t]   Simulating distance calculation (%0d cycles)...", $time, cycles);
            repeat(cycles) @(posedge clk);
            distance_done = 1;
            @(posedge clk);
            distance_done = 0;
        end
    endtask
    
    // Simulate test sample loading
    task simulate_test_load;
        input integer num_feat;
        integer i;
        begin
            $display("[%0t]   Simulating test sample loading (%0d features)...", $time, num_feat);
            for (i = 0; i < num_feat; i = i + 1) begin
                @(posedge clk);
            end
            test_sample_loaded = 1;
            @(posedge clk);
            test_sample_loaded = 0;
        end
    endtask
    
    // =========================================================================
    // State Transition Monitor
    // =========================================================================
    always @(posedge clk) begin
        if (current_state !== prev_state) begin
            $display("[%0t] State transition: %s -> %s", $time, 
                     get_state_name(prev_state), state_name);
            state_change_count = state_change_count + 1;
            prev_state = current_state;
        end
    end
    
    function [200:0] get_state_name;
        input [3:0] state;
        begin
            case (state)
                4'd0:  get_state_name = "IDLE";
                4'd1:  get_state_name = "LOAD_TEST_SAMPLE";
                4'd2:  get_state_name = "STORE_SAMPLE_LABELS";
                4'd3:  get_state_name = "STORE_SAMPLES";
                4'd4:  get_state_name = "LOAD_SAMPLE_FEATURES";
                4'd5:  get_state_name = "CALCULATE_DISTANCE";
                4'd6:  get_state_name = "STORE_DISTANCE";
                4'd7:  get_state_name = "SORT_K_NEAREST";
                4'd8:  get_state_name = "LOAD_FEATURES";
                4'd9:  get_state_name = "MAJORITY_LABELING";
                4'd10: get_state_name = "STORE_TEST_SAMPLE";
                4'd11: get_state_name = "OUTPUT_LABEL";
                default: get_state_name = "UNKNOWN";
            endcase
        end
    endfunction
    
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
        error_count = 0;
        state_change_count = 0;
        prev_state = 4'd0;
        
        $display("\n");
        $display("========================================");
        $display("KNN Control Unit Testbench");
        $display("========================================");
        $display("Configuration:");
        $display("  NUM_SAMPLES  = %0d", NUM_SAMPLES);
        $display("  NUM_FEATURES = %0d", NUM_FEATURES);
        $display("  K            = %0d", K);
        $display("========================================\n");
        
        // =====================================================================
        // Test 1: Reset and Initial State
        // =====================================================================
        $display("\n========================================");
        $display("Test 1: Reset and Initial State");
        $display("========================================");
        reset_system();
        @(posedge clk);
        
        check_state(4'd0, "After reset, FSM should be in IDLE");
        check_signal(busy, 1'b0, "busy signal in IDLE");
        check_signal(classification_done, 1'b0, "classification_done in IDLE");
        
        // =====================================================================
        // Test 2: Start Classification - IDLE to LOAD_TEST_SAMPLE
        // =====================================================================
        $display("\n========================================");
        $display("Test 2: Start Classification");
        $display("========================================");
        
        @(posedge clk);
        start_classify = 1;
        @(posedge clk);
        start_classify = 0;
        @(posedge clk);
        
        check_state(4'd1, "After start_classify, should enter LOAD_TEST_SAMPLE");
        check_signal(busy, 1'b1, "busy signal after start");
        check_signal(load_test_sample, 1'b1, "load_test_sample should be high");
        
        // =====================================================================
        // Test 3: Load Test Sample
        // =====================================================================
        $display("\n========================================");
        $display("Test 3: Load Test Sample");
        $display("========================================");
        
        simulate_test_load(NUM_FEATURES);
        repeat(2) @(posedge clk);
        
        check_state(4'd10, "After test loaded, should be in STORE_TEST_SAMPLE");
        
        // Wait for test features to be stored
        repeat(NUM_FEATURES + 2) @(posedge clk);
        
        check_state(4'd4, "Should transition to LOAD_SAMPLE_FEATURES");
        
        // =====================================================================
        // Test 4: Distance Calculation Loop
        // =====================================================================
        $display("\n========================================");
        $display("Test 4: Distance Calculation Loop");
        $display("========================================");
        
        // Process first sample
        $display("[%0t] Processing sample 0...", $time);
        repeat(NUM_FEATURES + 2) @(posedge clk);
        
        check_state(4'd5, "Should be in CALCULATE_DISTANCE");
        check_signal(en_dist_calc, 1'b1, "en_dist_calc in CALCULATE_DISTANCE");
        check_signal(calculate_distance, 1'b1, "calculate_distance pulse");
        
        simulate_distance_calc(5);
        @(posedge clk);
        
        check_state(4'd6, "After distance_done, should be in STORE_DISTANCE");
        
        // Check if it loops back for next sample
        @(posedge clk);
        if (current_sample_idx < num_samples - 1) begin
            check_state(4'd4, "Should loop back to LOAD_SAMPLE_FEATURES for next sample");
        end
        
        // Process remaining samples
        integer i;
        for (i = 1; i < NUM_SAMPLES; i = i + 1) begin
            $display("[%0t] Processing sample %0d...", $time, i);
            repeat(NUM_FEATURES + 2) @(posedge clk);
            simulate_distance_calc(5);
            @(posedge clk);
        end
        
        @(posedge clk);
        check_state(4'd7, "After all samples, should enter SORT_K_NEAREST");
        
        // =====================================================================
        // Test 5: Sorting Phase
        // =====================================================================
        $display("\n========================================");
        $display("Test 5: Sorting Phase");
        $display("========================================");
        
        check_signal(en_sort, 1'b1, "en_sort in SORT_K_NEAREST");
        check_signal(sort_start, 1'b1, "sort_start pulse");
        
        // Simulate sorting completion
        repeat(10) @(posedge clk);
        sort_done = 1;
        @(posedge clk);
        sort_done = 0;
        @(posedge clk);
        
        check_state(4'd8, "After sort_done, should enter LOAD_FEATURES");
        
        // =====================================================================
        // Test 6: Load K-Best Features
        // =====================================================================
        $display("\n========================================");
        $display("Test 6: Load K-Best Features");
        $display("========================================");
        
        check_signal(kbest_ren, 1'b1, "kbest_ren in LOAD_FEATURES");
        check_signal(label_ren, 1'b1, "label_ren in LOAD_FEATURES");
        
        repeat(K + 2) @(posedge clk);
        
        check_state(4'd9, "After loading K features, should enter MAJORITY_LABELING");
        
        // =====================================================================
        // Test 7: Majority Voting
        // =====================================================================
        $display("\n========================================");
        $display("Test 7: Majority Voting");
        $display("========================================");
        
        check_signal(en_majority_labeling, 1'b1, "en_majority_labeling");
        check_signal(majority_start, 1'b1, "majority_start pulse");
        
        // Simulate majority voting completion
        repeat(5) @(posedge clk);
        majority_done = 1;
        @(posedge clk);
        majority_done = 0;
        @(posedge clk);
        
        check_state(4'd11, "After majority_done, should enter OUTPUT_LABEL");
        
        // =====================================================================
        // Test 8: Output and Return to IDLE
        // =====================================================================
        $display("\n========================================");
        $display("Test 8: Output and Return to IDLE");
        $display("========================================");
        
        check_signal(classification_done, 1'b1, "classification_done pulse");
        
        @(posedge clk);
        check_state(4'd0, "Should return to IDLE");
        check_signal(busy, 1'b0, "busy should be low in IDLE");
        
        // =====================================================================
        // Test 9: Multiple Classifications
        // =====================================================================
        $display("\n========================================");
        $display("Test 9: Multiple Sequential Classifications");
        $display("========================================");
        
        // Start second classification
        repeat(5) @(posedge clk);
        start_classify = 1;
        @(posedge clk);
        start_classify = 0;
        
        check_state(4'd1, "Should enter LOAD_TEST_SAMPLE again");
        
        // Let it run through quickly
        simulate_test_load(NUM_FEATURES);
        repeat(NUM_FEATURES + 5) @(posedge clk);
        
        // Process all samples quickly
        for (i = 0; i < NUM_SAMPLES; i = i + 1) begin
            repeat(NUM_FEATURES + 2) @(posedge clk);
            simulate_distance_calc(3);
        end
        
        repeat(5) @(posedge clk);
        sort_done = 1;
        @(posedge clk);
        sort_done = 0;
        
        repeat(K + 5) @(posedge clk);
        majority_done = 1;
        @(posedge clk);
        majority_done = 0;
        
        @(posedge clk);
        check_state(4'd0, "Should return to IDLE after second classification");
        
        // =====================================================================
        // Final Report
        // =====================================================================
        repeat(10) @(posedge clk);
        
        $display("\n========================================");
        $display("Test Complete!");
        $display("========================================");
        $display("Test Statistics:");
        $display("  Total Tests:      %0d", test_count);
        $display("  Passed:           %0d (%.1f%%)", pass_count, (pass_count * 100.0) / test_count);
        $display("  Failed:           %0d (%.1f%%)", fail_count, (fail_count * 100.0) / test_count);
        $display("  State Transitions: %0d", state_change_count);
        $display("========================================\n");
        
        if (fail_count == 0)
            $display("✓ All tests PASSED!");
        else
            $display("✗ Some tests FAILED!");
        
        $finish;
    end
    
    // =========================================================================
    // Waveform Dump
    // =========================================================================
    initial begin
        $dumpfile("knn_control_unit.vcd");
        $dumpvars(0, tb_knn_control_unit);
    end

endmodule
