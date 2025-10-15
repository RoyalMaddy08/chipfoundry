`timescale 1ns / 1ps

// =============================================================================
// Testbench for KNN Sort Module (K-Best Selector)
// =============================================================================
module tb_knn_sort;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter K = 5;
    parameter NUM_SAMPLES = 20;
    parameter DISTANCE_WIDTH = 32;
    parameter INDEX_WIDTH = 8;
    parameter CLK_PERIOD = 10;
    
    // =========================================================================
    // DUT Signals
    // =========================================================================
    reg clk;
    reg rst_n;
    
    // Control interface
    reg sort_start;
    reg sort_clear;
    reg en_sort;
    
    // Distance stream input
    reg dist_valid;
    reg [DISTANCE_WIDTH-1:0] dist_data;
    reg [INDEX_WIDTH-1:0] dist_index;
    wire dist_ready;
    
    // K-best results output
    wire kbest_valid;
    wire [INDEX_WIDTH-1:0] kbest_index;
    wire [DISTANCE_WIDTH-1:0] kbest_distance;
    
    // Memory write interface
    wire kbest_wen;
    wire [$clog2(K)-1:0] kbest_waddr;
    wire [INDEX_WIDTH-1:0] kbest_wdata;
    
    // Status outputs
    wire sort_done;
    wire [$clog2(K+1)-1:0] num_neighbors;
    
    // =========================================================================
    // Test Storage
    // =========================================================================
    // Test distance arrays
    reg [DISTANCE_WIDTH-1:0] test_distances [0:NUM_SAMPLES-1];
    reg [INDEX_WIDTH-1:0] test_indices [0:NUM_SAMPLES-1];
    
    // Expected k-best results
    reg [DISTANCE_WIDTH-1:0] expected_distances [0:K-1];
    reg [INDEX_WIDTH-1:0] expected_indices [0:K-1];
    
    // Captured results
    reg [DISTANCE_WIDTH-1:0] captured_distances [0:K-1];
    reg [INDEX_WIDTH-1:0] captured_indices [0:K-1];
    integer capture_count;
    
    // =========================================================================
    // FSM State Monitoring
    // =========================================================================
    wire [2:0] current_state;
    assign current_state = dut.state;
    
    reg [200:0] state_name;
    always @(*) begin
        case (current_state)
            3'd0: state_name = "IDLE";
            3'd1: state_name = "ACCEPTING";
            3'd2: state_name = "COMPARE";
            3'd3: state_name = "INSERT";
            3'd4: state_name = "OUTPUT";
            3'd5: state_name = "DONE";
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
    knn_sort #(
        .K(K),
        .NUM_SAMPLES(NUM_SAMPLES),
        .DISTANCE_WIDTH(DISTANCE_WIDTH),
        .INDEX_WIDTH(INDEX_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        
        .sort_start(sort_start),
        .sort_clear(sort_clear),
        .en_sort(en_sort),
        
        .dist_valid(dist_valid),
        .dist_data(dist_data),
        .dist_index(dist_index),
        .dist_ready(dist_ready),
        
        .kbest_valid(kbest_valid),
        .kbest_index(kbest_index),
        .kbest_distance(kbest_distance),
        
        .kbest_wen(kbest_wen),
        .kbest_waddr(kbest_waddr),
        .kbest_wdata(kbest_wdata),
        
        .sort_done(sort_done),
        .num_neighbors(num_neighbors)
    );
    
    // =========================================================================
    // Test Statistics
    // =========================================================================
    integer test_count;
    integer pass_count;
    integer fail_count;
    
    // =========================================================================
    // Result Capture
    // =========================================================================
    always @(posedge clk) begin
        if (kbest_valid && capture_count < K) begin
            captured_distances[capture_count] <= kbest_distance;
            captured_indices[capture_count] <= kbest_index;
            $display("[%0t]   Captured k-best[%0d]: index=%0d, distance=%0d", 
                     $time, capture_count, kbest_index, kbest_distance);
            capture_count <= capture_count + 1;
        end
    end
    
    // =========================================================================
    // Helper Tasks
    // =========================================================================
    
    // Reset task
    task reset_system;
        begin
            $display("\n[%0t] === Performing System Reset ===", $time);
            rst_n = 0;
            sort_start = 0;
            sort_clear = 0;
            en_sort = 0;
            dist_valid = 0;
            dist_data = 0;
            dist_index = 0;
            capture_count = 0;
            
            repeat(5) @(posedge clk);
            rst_n = 1;
            repeat(2) @(posedge clk);
            
            $display("[%0t] Reset complete - State: %s", $time, state_name);
        end
    endtask
    
    // Initialize test data with random distances
    task init_random_distances;
        integer i;
        integer seed;
        begin
            seed = 12345;
            $display("\n[%0t] Initializing random test distances...", $time);
            for (i = 0; i < NUM_SAMPLES; i = i + 1) begin
                test_distances[i] = $random(seed) & 32'h0000FFFF;  // 16-bit random
                test_indices[i] = i;
                $display("  Sample[%0d]: distance=%0d", i, test_distances[i]);
            end
        end
    endtask
    
    // Initialize test data with known sequence
    task init_known_distances;
        begin
            $display("\n[%0t] Initializing known test distances...", $time);
            // Known sequence: descending order to test sorting
            test_distances[0]  = 32'd1000; test_indices[0]  = 0;
            test_distances[1]  = 32'd900;  test_indices[1]  = 1;
            test_distances[2]  = 32'd800;  test_indices[2]  = 2;
            test_distances[3]  = 32'd700;  test_indices[3]  = 3;
            test_distances[4]  = 32'd600;  test_indices[4]  = 4;
            test_distances[5]  = 32'd500;  test_indices[5]  = 5;
            test_distances[6]  = 32'd400;  test_indices[6]  = 6;
            test_distances[7]  = 32'd300;  test_indices[7]  = 7;
            test_distances[8]  = 32'd200;  test_indices[8]  = 8;
            test_distances[9]  = 32'd100;  test_indices[9]  = 9;
            test_distances[10] = 32'd50;   test_indices[10] = 10;
            test_distances[11] = 32'd25;   test_indices[11] = 11;
            test_distances[12] = 32'd75;   test_indices[12] = 12;
            test_distances[13] = 32'd150;  test_indices[13] = 13;
            test_distances[14] = 32'd250;  test_indices[14] = 14;
            test_distances[15] = 32'd350;  test_indices[15] = 15;
            test_distances[16] = 32'd450;  test_indices[16] = 16;
            test_distances[17] = 32'd550;  test_indices[17] = 17;
            test_distances[18] = 32'd650;  test_indices[18] = 18;
            test_distances[19] = 32'd750;  test_indices[19] = 19;
            
            // Expected K=5 smallest: indices 11(25), 10(50), 12(75), 9(100), 13(150)
            expected_distances[0] = 32'd25;  expected_indices[0] = 11;
            expected_distances[1] = 32'd50;  expected_indices[1] = 10;
            expected_distances[2] = 32'd75;  expected_indices[2] = 12;
            expected_distances[3] = 32'd100; expected_indices[3] = 9;
            expected_distances[4] = 32'd150; expected_indices[4] = 13;
            
            for (integer i = 0; i < NUM_SAMPLES; i = i + 1) begin
                $display("  Sample[%02d]: distance=%0d", i, test_distances[i]);
            end
            
            $display("\n  Expected K=%0d smallest:", K);
            for (integer i = 0; i < K; i = i + 1) begin
                $display("    [%0d]: index=%0d, distance=%0d", 
                         i, expected_indices[i], expected_distances[i]);
            end
        end
    endtask
    
    // Stream distances into sort module
    task stream_distances;
        input integer num_dist;
        integer i;
        begin
            $display("\n[%0t] Streaming %0d distances...", $time, num_dist);
            
            // Start sorting
            @(posedge clk);
            sort_start = 1;
            en_sort = 1;
            @(posedge clk);
            sort_start = 0;
            
            // Wait for ready
            wait(dist_ready);
            
            // Stream all distances
            for (i = 0; i < num_dist; i = i + 1) begin
                @(posedge clk);
                while (!dist_ready) @(posedge clk);
                
                dist_valid = 1;
                dist_data = test_distances[i];
                dist_index = test_indices[i];
                
                $display("[%0t]   Sending distance[%0d]: index=%0d, distance=%0d, state=%s", 
                         $time, i, dist_index, dist_data, state_name);
                
                @(posedge clk);
            end
            
            dist_valid = 0;
            
            $display("[%0t] All distances sent, waiting for sort_done...", $time);
            wait(sort_done);
            @(posedge clk);
            
            en_sort = 0;
            $display("[%0t] Sort complete!", $time);
        end
    endtask
    
    // Verify results
    task verify_results;
        integer i;
        integer errors;
        begin
            errors = 0;
            $display("\n[%0t] Verifying results...", $time);
            $display("  Expected vs Captured:");
            
            for (i = 0; i < K; i = i + 1) begin
                $display("  [%0d] Expected: idx=%02d dist=%0d | Captured: idx=%02d dist=%0d", 
                         i, 
                         expected_indices[i], expected_distances[i],
                         captured_indices[i], captured_distances[i]);
                
                if (captured_distances[i] !== expected_distances[i]) begin
                    $display("      ERROR: Distance mismatch!");
                    errors = errors + 1;
                end
                if (captured_indices[i] !== expected_indices[i]) begin
                    $display("      ERROR: Index mismatch!");
                    errors = errors + 1;
                end
            end
            
            test_count = test_count + 1;
            if (errors == 0) begin
                $display("\n  ✓ PASS: All K-best results match expected values");
                pass_count = pass_count + 1;
            end else begin
                $display("\n  ✗ FAIL: %0d mismatches found", errors);
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    // Check sorting property (results should be in ascending order)
    task check_sorting_property;
        integer i;
        integer errors;
        begin
            errors = 0;
            test_count = test_count + 1;
            
            $display("\n[%0t] Checking sorting property (ascending order)...", $time);
            for (i = 0; i < K-1; i = i + 1) begin
                if (captured_distances[i] > captured_distances[i+1]) begin
                    $display("  ERROR: Order violation at position %0d: %0d > %0d", 
                             i, captured_distances[i], captured_distances[i+1]);
                    errors = errors + 1;
                end
            end
            
            if (errors == 0) begin
                $display("  ✓ PASS: Results are properly sorted");
                pass_count = pass_count + 1;
            end else begin
                $display("  ✗ FAIL: Sorting property violated");
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    // Test with fewer samples than K
    task test_fewer_than_k;
        integer num_dist;
        integer i;
        begin
            num_dist = K - 2;
            $display("\n[%0t] Testing with fewer samples than K (%0d < %0d)...", 
                     $time, num_dist, K);
            
            capture_count = 0;
            
            @(posedge clk);
            sort_start = 1;
            en_sort = 1;
            @(posedge clk);
            sort_start = 0;
            
            wait(dist_ready);
            
            for (i = 0; i < num_dist; i = i + 1) begin
                @(posedge clk);
                dist_valid = 1;
                dist_data = test_distances[i];
                dist_index = test_indices[i];
                @(posedge clk);
            end
            
            dist_valid = 0;
            wait(sort_done);
            @(posedge clk);
            en_sort = 0;
            
            test_count = test_count + 1;
            if (num_neighbors == num_dist) begin
                $display("  ✓ PASS: num_neighbors = %0d (correct)", num_neighbors);
                pass_count = pass_count + 1;
            end else begin
                $display("  ✗ FAIL: num_neighbors = %0d (expected %0d)", num_neighbors, num_dist);
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    // =========================================================================
    // Timeout Watchdog
    // =========================================================================
    initial begin
        #1000000;  // 1ms timeout
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
        $display("KNN Sort Module Testbench");
        $display("========================================");
        $display("Configuration:");
        $display("  K             = %0d", K);
        $display("  NUM_SAMPLES   = %0d", NUM_SAMPLES);
        $display("  DISTANCE_WIDTH= %0d", DISTANCE_WIDTH);
        $display("  INDEX_WIDTH   = %0d", INDEX_WIDTH);
        $display("========================================\n");
        
        // =====================================================================
        // Test 1: Basic Sorting with Known Data
        // =====================================================================
        $display("\n========================================");
        $display("Test 1: Basic K-Best Selection");
        $display("========================================");
        
        reset_system();
        init_known_distances();
        capture_count = 0;
        
        stream_distances(NUM_SAMPLES);
        
        repeat(10) @(posedge clk);
        
        verify_results();
        check_sorting_property();
        
        // =====================================================================
        // Test 2: Edge Case - Identical Distances
        // =====================================================================
        $display("\n========================================");
        $display("Test 2: Identical Distances");
        $display("========================================");
        
        reset_system();
        
        // All same distance
        for (integer i = 0; i < NUM_SAMPLES; i = i + 1) begin
            test_distances[i] = 32'd100;
            test_indices[i] = i;
        end
        
        for (integer i = 0; i < K; i = i + 1) begin
            expected_distances[i] = 32'd100;
            expected_indices[i] = i;  // Should get first K indices
        end
        
        capture_count = 0;
        stream_distances(NUM_SAMPLES);
        
        repeat(10) @(posedge clk);
        
        // Just check that we got K results with correct distance
        test_count = test_count + 1;
        if (num_neighbors == K && captured_distances[0] == 32'd100) begin
            $display("  ✓ PASS: Handled identical distances correctly");
            pass_count = pass_count + 1;
        end else begin
            $display("  ✗ FAIL: Issue with identical distances");
            fail_count = fail_count + 1;
        end
        
        // =====================================================================
        // Test 3: Already Sorted Input
        // =====================================================================
        $display("\n========================================");
        $display("Test 3: Already Sorted Input");
        $display("========================================");
        
        reset_system();
        
        // Ascending order
        for (integer i = 0; i < NUM_SAMPLES; i = i + 1) begin
            test_distances[i] = i * 10;
            test_indices[i] = i;
        end
        
        for (integer i = 0; i < K; i = i + 1) begin
            expected_distances[i] = i * 10;
            expected_indices[i] = i;
        end
        
        capture_count = 0;
        stream_distances(NUM_SAMPLES);
        
        repeat(10) @(posedge clk);
        verify_results();
        
        // =====================================================================
        // Test 4: Reverse Sorted Input
        // =====================================================================
        $display("\n========================================");
        $display("Test 4: Reverse Sorted Input");
        $display("========================================");
        
        reset_system();
        
        // Descending order
        for (integer i = 0; i < NUM_SAMPLES; i = i + 1) begin
            test_distances[i] = (NUM_SAMPLES - i) * 10;
            test_indices[i] = i;
        end
        
        for (integer i = 0; i < K; i = i + 1) begin
            expected_distances[i] = (i + 1) * 10;
            expected_indices[i] = NUM_SAMPLES - i - 1;
        end
        
        capture_count = 0;
        stream_distances(NUM_SAMPLES);
        
        repeat(10) @(posedge clk);
        verify_results();
        
        // =====================================================================
        // Test 5: Fewer Samples than K
        // =====================================================================
        $display("\n========================================");
        $display("Test 5: Fewer Samples than K");
        $display("========================================");
        
        reset_system();
        test_fewer_than_k();
        
        // =====================================================================
        // Test 6: Clear and Restart
        // =====================================================================
        $display("\n========================================");
        $display("Test 6: Clear and Restart");
        $display("========================================");
        
        reset_system();
        
        @(posedge clk);
        sort_clear = 1;
        @(posedge clk);
        sort_clear = 0;
        
        $display("  Cleared sort buffer, running new sort...");
        
        capture_count = 0;
        stream_distances(NUM_SAMPLES);
        
        test_count = test_count + 1;
        if (sort_done) begin
            $display("  ✓ PASS: Successfully restarted after clear");
            pass_count = pass_count + 1;
        end else begin
            $display("  ✗ FAIL: Did not complete after clear");
            fail_count = fail_count + 1;
        end
        
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
                3'd1: get_state_name = "ACCEPTING";
                3'd2: get_state_name = "COMPARE";
                3'd3: get_state_name = "INSERT";
                3'd4: get_state_name = "OUTPUT";
                3'd5: get_state_name = "DONE";
                default: get_state_name = "UNKNOWN";
            endcase
        end
    endfunction
    
    // =========================================================================
    // Waveform Dump
    // =========================================================================
    initial begin
        $dumpfile("knn_sort.vcd");
        $dumpvars(0, tb_knn_sort);
    end

endmodule
