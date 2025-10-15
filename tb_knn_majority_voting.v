`timescale 1ns / 1ps

// =============================================================================
// Testbench for KNN Majority Voting Module
// =============================================================================
module tb_knn_majority_voting;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter K = 7;
    parameter NUM_CLASSES = 5;
    parameter LABEL_WIDTH = 4;
    parameter COUNT_WIDTH = 8;
    parameter CLK_PERIOD = 10;
    
    // =========================================================================
    // DUT Signals
    // =========================================================================
    reg clk;
    reg rst_n;
    
    // Control interface
    reg majority_start;
    reg en_majority_labeling;
    
    // Label input (streaming mode - not used in this config)
    reg label_valid;
    reg [LABEL_WIDTH-1:0] label_data;
    wire label_ready;
    
    // Memory read interface
    reg [LABEL_WIDTH-1:0] label_rdata_q;
    wire label_ren;
    wire [$clog2(K)-1:0] label_raddr;
    
    // Configuration
    reg [$clog2(K+1)-1:0] k_value;
    reg [$clog2(NUM_CLASSES)-1:0] num_classes;
    
    // Result output
    wire result_valid;
    wire [LABEL_WIDTH-1:0] result_label;
    wire [COUNT_WIDTH-1:0] result_count;
    
    // Status
    wire majority_done;
    
    // =========================================================================
    // Test Data Storage
    // =========================================================================
    // Label memory to simulate K-best label storage
    reg [LABEL_WIDTH-1:0] label_memory [0:K-1];
    
    // Test scenarios
    reg [LABEL_WIDTH-1:0] test_labels [0:6][0:K-1];  // 7 test cases, K labels each
    reg [LABEL_WIDTH-1:0] expected_winners [0:6];
    reg [COUNT_WIDTH-1:0] expected_counts [0:6];
    
    // =========================================================================
    // FSM State Monitoring
    // =========================================================================
    wire [2:0] current_state;
    assign current_state = dut.state;
    
    reg [200:0] state_name;
    always @(*) begin
        case (current_state)
            3'd0: state_name = "IDLE";
            3'd1: state_name = "LOAD_LABELS";
            3'd2: state_name = "COUNT_VOTES";
            3'd3: state_name = "FIND_MAX";
            3'd4: state_name = "OUTPUT_RESULT";
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
        if (label_ren) begin
            label_rdata_q <= label_memory[label_raddr];
        end
    end
    
    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    knn_majority_voting #(
        .K(K),
        .NUM_CLASSES(NUM_CLASSES),
        .LABEL_WIDTH(LABEL_WIDTH),
        .COUNT_WIDTH(COUNT_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        
        .majority_start(majority_start),
        .en_majority_labeling(en_majority_labeling),
        
        .label_valid(label_valid),
        .label_data(label_data),
        .label_ready(label_ready),
        
        .label_rdata_q(label_rdata_q),
        .label_ren(label_ren),
        .label_raddr(label_raddr),
        
        .k_value(k_value),
        .num_classes(num_classes),
        
        .result_valid(result_valid),
        .result_label(result_label),
        .result_count(result_count),
        
        .majority_done(majority_done)
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
            majority_start = 0;
            en_majority_labeling = 0;
            label_valid = 0;
            label_data = 0;
            label_rdata_q = 0;
            k_value = K;
            num_classes = NUM_CLASSES;
            
            repeat(5) @(posedge clk);
            rst_n = 1;
            repeat(2) @(posedge clk);
            
            $display("[%0t] Reset complete - State: %s", $time, state_name);
        end
    endtask
    
    // Initialize test scenarios
    task init_test_scenarios;
        begin
            $display("\n[%0t] Initializing test scenarios...", $time);
            
            // Test 0: Clear majority - All same class
            // Labels: [0, 0, 0, 0, 0, 0, 0] -> Winner: 0, Count: 7
            test_labels[0][0] = 4'd0; test_labels[0][1] = 4'd0; test_labels[0][2] = 4'd0;
            test_labels[0][3] = 4'd0; test_labels[0][4] = 4'd0; test_labels[0][5] = 4'd0;
            test_labels[0][6] = 4'd0;
            expected_winners[0] = 4'd0;
            expected_counts[0] = 8'd7;
            
            // Test 1: Clear majority - One class dominates
            // Labels: [1, 1, 1, 1, 2, 3, 4] -> Winner: 1, Count: 4
            test_labels[1][0] = 4'd1; test_labels[1][1] = 4'd1; test_labels[1][2] = 4'd1;
            test_labels[1][3] = 4'd1; test_labels[1][4] = 4'd2; test_labels[1][5] = 4'd3;
            test_labels[1][6] = 4'd4;
            expected_winners[1] = 4'd1;
            expected_counts[1] = 8'd4;
            
            // Test 2: Close vote
            // Labels: [0, 0, 0, 1, 1, 1, 2] -> Winner: 0 or 1 (both have 3), expect 0 (lower index)
            test_labels[2][0] = 4'd0; test_labels[2][1] = 4'd0; test_labels[2][2] = 4'd0;
            test_labels[2][3] = 4'd1; test_labels[2][4] = 4'd1; test_labels[2][5] = 4'd1;
            test_labels[2][6] = 4'd2;
            expected_winners[2] = 4'd0;  // Tie-breaker: lowest class index
            expected_counts[2] = 8'd3;
            
            // Test 3: All different classes
            // Labels: [0, 1, 2, 3, 4, 0, 1] -> Winner: 0 or 1 (both have 2)
            test_labels[3][0] = 4'd0; test_labels[3][1] = 4'd1; test_labels[3][2] = 4'd2;
            test_labels[3][3] = 4'd3; test_labels[3][4] = 4'd4; test_labels[3][5] = 4'd0;
            test_labels[3][6] = 4'd1;
            expected_winners[3] = 4'd0;  // Tie-breaker
            expected_counts[3] = 8'd2;
            
            // Test 4: Two classes compete
            // Labels: [2, 2, 2, 3, 3, 3, 3] -> Winner: 3, Count: 4
            test_labels[4][0] = 4'd2; test_labels[4][1] = 4'd2; test_labels[4][2] = 4'd2;
            test_labels[4][3] = 4'd3; test_labels[4][4] = 4'd3; test_labels[4][5] = 4'd3;
            test_labels[4][6] = 4'd3;
            expected_winners[4] = 4'd3;
            expected_counts[4] = 8'd4;
            
            // Test 5: Last class wins
            // Labels: [4, 4, 4, 4, 0, 1, 2] -> Winner: 4, Count: 4
            test_labels[5][0] = 4'd4; test_labels[5][1] = 4'd4; test_labels[5][2] = 4'd4;
            test_labels[5][3] = 4'd4; test_labels[5][4] = 4'd0; test_labels[5][5] = 4'd1;
            test_labels[5][6] = 4'd2;
            expected_winners[5] = 4'd4;
            expected_counts[5] = 8'd4;
            
            // Test 6: Mixed with sparse votes
            // Labels: [1, 2, 1, 3, 1, 4, 1] -> Winner: 1, Count: 4
            test_labels[6][0] = 4'd1; test_labels[6][1] = 4'd2; test_labels[6][2] = 4'd1;
            test_labels[6][3] = 4'd3; test_labels[6][4] = 4'd1; test_labels[6][5] = 4'd4;
            test_labels[6][6] = 4'd1;
            expected_winners[6] = 4'd1;
            expected_counts[6] = 8'd4;
            
            $display("  Test scenarios initialized");
        end
    endtask
    
    // Load labels into memory
    task load_labels;
        input integer test_idx;
        integer i;
        begin
            $display("\n[%0t] Loading test %0d labels into memory:", $time, test_idx);
            $display("  Labels: [", );
            for (i = 0; i < K; i = i + 1) begin
                label_memory[i] = test_labels[test_idx][i];
                if (i < K-1)
                    $write("%0d, ", test_labels[test_idx][i]);
                else
                    $write("%0d", test_labels[test_idx][i]);
            end
            $display("]");
            $display("  Expected: Winner=%0d, Count=%0d", 
                     expected_winners[test_idx], expected_counts[test_idx]);
        end
    endtask
    
    // Run majority voting
    task run_majority_voting;
        begin
            $display("\n[%0t] Starting majority voting...", $time);
            
            @(posedge clk);
            majority_start = 1;
            en_majority_labeling = 1;
            @(posedge clk);
            majority_start = 0;
            
            $display("[%0t] Waiting for majority_done...", $time);
            wait(majority_done);
            @(posedge clk);
            
            en_majority_labeling = 0;
            $display("[%0t] Majority voting complete!", $time);
        end
    endtask
    
    // Verify results
    task verify_result;
        input integer test_idx;
        begin
            $display("\n[%0t] Verifying results for test %0d:", $time, test_idx);
            $display("  Expected: Winner=%0d, Count=%0d", 
                     expected_winners[test_idx], expected_counts[test_idx]);
            $display("  Got:      Winner=%0d, Count=%0d", result_label, result_count);
            
            test_count = test_count + 1;
            
            if (result_label === expected_winners[test_idx] && 
                result_count === expected_counts[test_idx]) begin
                $display("  ✓ PASS: Results match exactly");
                pass_count = pass_count + 1;
            end else if (result_label === expected_winners[test_idx]) begin
                $display("  ⚠ PARTIAL: Winner correct but count mismatch");
                $display("             Count expected=%0d, got=%0d", 
                         expected_counts[test_idx], result_count);
                fail_count = fail_count + 1;
            end else begin
                $display("  ✗ FAIL: Winner mismatch");
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    // Test with different K values
    task test_variable_k;
        input integer test_k;
        input integer test_idx;
        integer i;
        reg [LABEL_WIDTH-1:0] temp_winner;
        reg [COUNT_WIDTH-1:0] temp_count;
        begin
            $display("\n[%0t] Testing with K=%0d (using test %0d labels)", 
                     $time, test_k, test_idx);
            
            k_value = test_k;
            
            // Load only first test_k labels
            for (i = 0; i < test_k; i = i + 1) begin
                label_memory[i] = test_labels[test_idx][i];
            end
            
            run_majority_voting();
            
            $display("  Result: Winner=%0d, Count=%0d", result_label, result_count);
            
            // Just check that we got a valid result
            test_count = test_count + 1;
            if (result_valid && majority_done) begin
                $display("  ✓ PASS: Valid result obtained with K=%0d", test_k);
                pass_count = pass_count + 1;
            end else begin
                $display("  ✗ FAIL: No valid result with K=%0d", test_k);
                fail_count = fail_count + 1;
            end
            
            k_value = K;  // Reset to default
        end
    endtask
    
    // Display vote distribution
    task display_vote_distribution;
        input integer test_idx;
        integer i, j;
        integer class_counts [0:NUM_CLASSES-1];
        begin
            // Count votes for each class
            for (i = 0; i < NUM_CLASSES; i = i + 1) begin
                class_counts[i] = 0;
            end
            
            for (i = 0; i < K; i = i + 1) begin
                class_counts[test_labels[test_idx][i]] = 
                    class_counts[test_labels[test_idx][i]] + 1;
            end
            
            $display("\n  Vote Distribution:");
            for (i = 0; i < NUM_CLASSES; i = i + 1) begin
                if (class_counts[i] > 0) begin
                    $display("    Class %0d: %0d votes", i, class_counts[i]);
                end
            end
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
        $display("KNN Majority Voting Testbench");
        $display("========================================");
        $display("Configuration:");
        $display("  K            = %0d", K);
        $display("  NUM_CLASSES  = %0d", NUM_CLASSES);
        $display("  LABEL_WIDTH  = %0d", LABEL_WIDTH);
        $display("  COUNT_WIDTH  = %0d", COUNT_WIDTH);
        $display("========================================\n");
        
        // =====================================================================
        // Initialize
        // =====================================================================
        reset_system();
        init_test_scenarios();
        
        // =====================================================================
        // Test 1: Clear Majority - All Same Class
        // =====================================================================
        $display("\n========================================");
        $display("Test 1: Clear Majority (All Same)");
        $display("========================================");
        
        load_labels(0);
        display_vote_distribution(0);
        run_majority_voting();
        verify_result(0);
        
        // =====================================================================
        // Test 2: Clear Majority - One Dominates
        // =====================================================================
        $display("\n========================================");
        $display("Test 2: Clear Majority (One Dominates)");
        $display("========================================");
        
        reset_system();
        load_labels(1);
        display_vote_distribution(1);
        run_majority_voting();
        verify_result(1);
        
        // =====================================================================
        // Test 3: Close Vote (Tie)
        // =====================================================================
        $display("\n========================================");
        $display("Test 3: Close Vote (Tie-Breaker)");
        $display("========================================");
        
        reset_system();
        load_labels(2);
        display_vote_distribution(2);
        run_majority_voting();
        verify_result(2);
        
        // =====================================================================
        // Test 4: All Different Classes
        // =====================================================================
        $display("\n========================================");
        $display("Test 4: All Different Classes");
        $display("========================================");
        
        reset_system();
        load_labels(3);
        display_vote_distribution(3);
        run_majority_voting();
        verify_result(3);
        
        // =====================================================================
        // Test 5: Two Classes Compete
        // =====================================================================
        $display("\n========================================");
        $display("Test 5: Two Classes Compete");
        $display("========================================");
        
        reset_system();
        load_labels(4);
        display_vote_distribution(4);
        run_majority_voting();
        verify_result(4);
        
        // =====================================================================
        // Test 6: Last Class Wins
        // =====================================================================
        $display("\n========================================");
        $display("Test 6: Last Class Wins");
        $display("========================================");
        
        reset_system();
        load_labels(5);
        display_vote_distribution(5);
        run_majority_voting();
        verify_result(5);
        
        // =====================================================================
        // Test 7: Mixed Sparse Votes
        // =====================================================================
        $display("\n========================================");
        $display("Test 7: Mixed Sparse Votes");
        $display("========================================");
        
        reset_system();
        load_labels(6);
        display_vote_distribution(6);
        run_majority_voting();
        verify_result(6);
        
        // =====================================================================
        // Test 8: Variable K Values
        // =====================================================================
        $display("\n========================================");
        $display("Test 8: Variable K Values");
        $display("========================================");
        
        reset_system();
        test_variable_k(3, 1);  // K=3
        
        reset_system();
        test_variable_k(5, 1);  // K=5
        
        reset_system();
        test_variable_k(1, 1);  // K=1 (edge case)
        
        // =====================================================================
        // Test 9: Multiple Sequential Votes
        // =====================================================================
        $display("\n========================================");
        $display("Test 9: Multiple Sequential Votes");
        $display("========================================");
        
        for (integer i = 0; i < 3; i = i + 1) begin
            $display("\n  --- Iteration %0d ---", i+1);
            reset_system();
            load_labels(i);
            run_majority_voting();
            verify_result(i);
        end
        
        // =====================================================================
        // Test 10: FSM State Verification
        // =====================================================================
        $display("\n========================================");
        $display("Test 10: FSM State Verification");
        $display("========================================");
        
        reset_system();
        
        test_count = test_count + 1;
        if (current_state == 3'd0) begin
            $display("  ✓ PASS: In IDLE state after reset");
            pass_count = pass_count + 1;
        end else begin
            $display("  ✗ FAIL: Not in IDLE after reset (state=%0d)", current_state);
            fail_count = fail_count + 1;
        end
        
        load_labels(0);
        
        @(posedge clk);
        majority_start = 1;
        en_majority_labeling = 1;
        @(posedge clk);
        majority_start = 0;
        @(posedge clk);
        
        test_count = test_count + 1;
        if (current_state == 3'd1) begin
            $display("  ✓ PASS: Transitioned to LOAD_LABELS");
            pass_count = pass_count + 1;
        end else begin
            $display("  ✗ FAIL: Not in LOAD_LABELS state");
            fail_count = fail_count + 1;
        end
        
        wait(majority_done);
        en_majority_labeling = 0;
        
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
                3'd1: get_state_name = "LOAD_LABELS";
                3'd2: get_state_name = "COUNT_VOTES";
                3'd3: get_state_name = "FIND_MAX";
                3'd4: get_state_name = "OUTPUT_RESULT";
                default: get_state_name = "UNKNOWN";
            endcase
        end
    endfunction
    
    // =========================================================================
    // Waveform Dump
    // =========================================================================
    initial begin
        $dumpfile("knn_majority_voting.vcd");
        $dumpvars(0, tb_knn_majority_voting);
    end

endmodule
