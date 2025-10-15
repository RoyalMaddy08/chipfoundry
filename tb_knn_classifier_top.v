`timescale 1ns / 1ps

// =============================================================================
// Testbench for KNN Classifier Top Module
// =============================================================================
module tb_knn_classifier_top;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter DATA_WIDTH = 16;
    parameter NUM_FEATURES = 4;      // Reduced for easier testing
    parameter NUM_SAMPLES = 10;      // Reduced for faster simulation
    parameter LABEL_WIDTH = 4;
    parameter NUM_CLASSES = 3;
    parameter ADDR_WIDTH = 8;
    parameter DISTANCE_WIDTH = 32;
    parameter K = 3;
    
    parameter CLK_PERIOD = 10;  // 100MHz clock
    
    // =========================================================================
    // DUT Signals
    // =========================================================================
    reg clk;
    reg rst_n;
    
    // Training interface
    reg train_mode;
    reg train_sample_wen;
    reg [ADDR_WIDTH-1:0] train_sample_addr;
    reg [DATA_WIDTH-1:0] train_sample_data;
    reg train_label_wen;
    reg [ADDR_WIDTH-1:0] train_label_addr;
    reg [LABEL_WIDTH-1:0] train_label_data;
    
    // Classification interface
    reg classify_start;
    reg test_feature_valid;
    reg [DATA_WIDTH-1:0] test_feature_data;
    
    // Configuration
    reg [ADDR_WIDTH-1:0] cfg_num_samples;
    reg [$clog2(NUM_FEATURES)-1:0] cfg_num_features;
    reg [$clog2(K+1)-1:0] cfg_k_value;
    
    // Outputs
    wire classify_done;
    wire [LABEL_WIDTH-1:0] result_label;
    wire [$clog2(K+1)-1:0] result_confidence;
    wire busy;
    
    // =========================================================================
    // Test Data Storage
    // =========================================================================
    // Training dataset: [sample][feature]
    reg [DATA_WIDTH-1:0] training_samples [0:NUM_SAMPLES-1][0:NUM_FEATURES-1];
    reg [LABEL_WIDTH-1:0] training_labels [0:NUM_SAMPLES-1];
    
    // Test samples
    reg [DATA_WIDTH-1:0] test_samples [0:2][0:NUM_FEATURES-1];  // 3 test cases
    reg [LABEL_WIDTH-1:0] expected_labels [0:2];
    
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
    knn_classifier_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_FEATURES(NUM_FEATURES),
        .NUM_SAMPLES(NUM_SAMPLES),
        .LABEL_WIDTH(LABEL_WIDTH),
        .NUM_CLASSES(NUM_CLASSES),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DISTANCE_WIDTH(DISTANCE_WIDTH),
        .K(K)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        
        .train_mode(train_mode),
        .train_sample_wen(train_sample_wen),
        .train_sample_addr(train_sample_addr),
        .train_sample_data(train_sample_data),
        .train_label_wen(train_label_wen),
        .train_label_addr(train_label_addr),
        .train_label_data(train_label_data),
        
        .classify_start(classify_start),
        .test_feature_valid(test_feature_valid),
        .test_feature_data(test_feature_data),
        
        .cfg_num_samples(cfg_num_samples),
        .cfg_num_features(cfg_num_features),
        .cfg_k_value(cfg_k_value),
        
        .classify_done(classify_done),
        .result_label(result_label),
        .result_confidence(result_confidence),
        .busy(busy)
    );
    
    // =========================================================================
    // Test Statistics
    // =========================================================================
    integer test_count;
    integer pass_count;
    integer fail_count;
    
    // =========================================================================
    // Initialize Test Data
    // =========================================================================
    initial begin
        initialize_training_data();
        initialize_test_data();
    end
    
    // Create simple 2D separable dataset
    task initialize_training_data;
        integer i;
        begin
            // Class 0: Small values (around 10)
            training_samples[0][0] = 16'd10;  training_samples[0][1] = 16'd12;
            training_samples[0][2] = 16'd11;  training_samples[0][3] = 16'd9;
            training_labels[0] = 4'd0;
            
            training_samples[1][0] = 16'd8;   training_samples[1][1] = 16'd10;
            training_samples[1][2] = 16'd12;  training_samples[1][3] = 16'd11;
            training_labels[1] = 4'd0;
            
            training_samples[2][0] = 16'd11;  training_samples[2][1] = 16'd13;
            training_samples[2][2] = 16'd10;  training_samples[2][3] = 16'd12;
            training_labels[2] = 4'd0;
            
            // Class 1: Medium values (around 50)
            training_samples[3][0] = 16'd50;  training_samples[3][1] = 16'd52;
            training_samples[3][2] = 16'd48;  training_samples[3][3] = 16'd51;
            training_labels[3] = 4'd1;
            
            training_samples[4][0] = 16'd49;  training_samples[4][1] = 16'd51;
            training_samples[4][2] = 16'd50;  training_samples[4][3] = 16'd52;
            training_labels[4] = 4'd1;
            
            training_samples[5][0] = 16'd51;  training_samples[5][1] = 16'd49;
            training_samples[5][2] = 16'd52;  training_samples[5][3] = 16'd50;
            training_labels[5] = 4'd1;
            
            // Class 2: Large values (around 100)
            training_samples[6][0] = 16'd100; training_samples[6][1] = 16'd102;
            training_samples[6][2] = 16'd99;  training_samples[6][3] = 16'd101;
            training_labels[6] = 4'd2;
            
            training_samples[7][0] = 16'd98;  training_samples[7][1] = 16'd100;
            training_samples[7][2] = 16'd101; training_samples[7][3] = 16'd99;
            training_labels[7] = 4'd2;
            
            training_samples[8][0] = 16'd101; training_samples[8][1] = 16'd99;
            training_samples[8][2] = 16'd100; training_samples[8][3] = 16'd102;
            training_labels[8] = 4'd2;
            
            training_samples[9][0] = 16'd99;  training_samples[9][1] = 16'd101;
            training_samples[9][2] = 16'd98;  training_samples[9][3] = 16'd100;
            training_labels[9] = 4'd2;
        end
    endtask
    
    task initialize_test_data;
        begin
            // Test case 0: Should classify as Class 0
            test_samples[0][0] = 16'd9;
            test_samples[0][1] = 16'd11;
            test_samples[0][2] = 16'd10;
            test_samples[0][3] = 16'd12;
            expected_labels[0] = 4'd0;
            
            // Test case 1: Should classify as Class 1
            test_samples[1][0] = 16'd48;
            test_samples[1][1] = 16'd50;
            test_samples[1][2] = 16'd51;
            test_samples[1][3] = 16'd49;
            expected_labels[1] = 4'd1;
            
            // Test case 2: Should classify as Class 2
            test_samples[2][0] = 16'd100;
            test_samples[2][1] = 16'd98;
            test_samples[2][2] = 16'd101;
            test_samples[2][3] = 16'd99;
            expected_labels[2] = 4'd2;
        end
    endtask
    
    // =========================================================================
    // Tasks for Common Operations
    // =========================================================================
    
    // Reset task
    task reset_system;
        begin
            rst_n = 0;
            train_mode = 0;
            train_sample_wen = 0;
            train_sample_addr = 0;
            train_sample_data = 0;
            train_label_wen = 0;
            train_label_addr = 0;
            train_label_data = 0;
            classify_start = 0;
            test_feature_valid = 0;
            test_feature_data = 0;
            cfg_num_samples = NUM_SAMPLES;
            cfg_num_features = NUM_FEATURES;
            cfg_k_value = K;
            
            repeat(5) @(posedge clk);
            rst_n = 1;
            repeat(2) @(posedge clk);
            
            $display("[%0t] System reset complete", $time);
        end
    endtask
    
    // Load training data into memory
    task load_training_data;
        integer i, j;
        begin
            $display("[%0t] Loading training data...", $time);
            train_mode = 1;
            
            // Load training samples (features)
            for (i = 0; i < NUM_SAMPLES; i = i + 1) begin
                for (j = 0; j < NUM_FEATURES; j = j + 1) begin
                    @(posedge clk);
                    train_sample_wen = 1;
                    train_sample_addr = (i * NUM_FEATURES) + j;
                    train_sample_data = training_samples[i][j];
                end
            end
            
            @(posedge clk);
            train_sample_wen = 0;
            
            // Load training labels
            for (i = 0; i < NUM_SAMPLES; i = i + 1) begin
                @(posedge clk);
                train_label_wen = 1;
                train_label_addr = i;
                train_label_data = training_labels[i];
            end
            
            @(posedge clk);
            train_label_wen = 0;
            train_mode = 0;
            
            $display("[%0t] Training data loaded: %0d samples, %0d features", 
                     $time, NUM_SAMPLES, NUM_FEATURES);
        end
    endtask
    
    // Classify a test sample
    task classify_sample;
        input integer test_idx;
        integer j;
        begin
            $display("[%0t] Starting classification for test sample %0d", $time, test_idx);
            
            // Start classification
            @(posedge clk);
            classify_start = 1;
            @(posedge clk);
            classify_start = 0;
            
            // Wait for system to request test features
            wait(busy);
            repeat(2) @(posedge clk);
            
            // Stream test features
            for (j = 0; j < NUM_FEATURES; j = j + 1) begin
                @(posedge clk);
                test_feature_valid = 1;
                test_feature_data = test_samples[test_idx][j];
                $display("[%0t]   Sending test feature[%0d] = %0d", $time, j, test_feature_data);
            end
            
            @(posedge clk);
            test_feature_valid = 0;
            test_feature_data = 0;
            
            // Wait for classification to complete
            $display("[%0t] Waiting for classification to complete...", $time);
            wait(classify_done);
            @(posedge clk);
            
            $display("[%0t] Classification complete!", $time);
            $display("        Result: Label = %0d, Confidence = %0d", result_label, result_confidence);
            $display("        Expected: Label = %0d", expected_labels[test_idx]);
            
            // Check result
            test_count = test_count + 1;
            if (result_label == expected_labels[test_idx]) begin
                $display("        ✓ PASS");
                pass_count = pass_count + 1;
            end else begin
                $display("        ✗ FAIL");
                fail_count = fail_count + 1;
            end
            
            repeat(5) @(posedge clk);
        end
    endtask
    
    // =========================================================================
    // Timeout Watchdog
    // =========================================================================
    initial begin
        #1000000;  // 1ms timeout
        $display("\n[ERROR] Simulation timeout!");
        $display("Test Statistics:");
        $display("  Total: %0d", test_count);
        $display("  Pass:  %0d", pass_count);
        $display("  Fail:  %0d", fail_count);
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
        $display("KNN Classifier Top Module Testbench");
        $display("========================================");
        $display("Configuration:");
        $display("  DATA_WIDTH    = %0d", DATA_WIDTH);
        $display("  NUM_FEATURES  = %0d", NUM_FEATURES);
        $display("  NUM_SAMPLES   = %0d", NUM_SAMPLES);
        $display("  NUM_CLASSES   = %0d", NUM_CLASSES);
        $display("  K             = %0d", K);
        $display("========================================\n");
        
        // Reset
        reset_system();
        
        // Load training data
        load_training_data();
        
        repeat(10) @(posedge clk);
        
        // Test Case 1: Classify sample from Class 0
        $display("\n========================================");
        $display("Test Case 1: Class 0 Sample");
        $display("========================================");
        classify_sample(0);
        
        // Test Case 2: Classify sample from Class 1
        $display("\n========================================");
        $display("Test Case 2: Class 1 Sample");
        $display("========================================");
        classify_sample(1);
        
        // Test Case 3: Classify sample from Class 2
        $display("\n========================================");
        $display("Test Case 3: Class 2 Sample");
        $display("========================================");
        classify_sample(2);
        
        // Final Report
        repeat(10) @(posedge clk);
        $display("\n========================================");
        $display("Test Complete!");
        $display("========================================");
        $display("Test Statistics:");
        $display("  Total: %0d", test_count);
        $display("  Pass:  %0d (%.1f%%)", pass_count, (pass_count * 100.0) / test_count);
        $display("  Fail:  %0d (%.1f%%)", fail_count, (fail_count * 100.0) / test_count);
        $display("========================================\n");
        
        if (fail_count == 0)
            $display("✓ All tests PASSED!");
        else
            $display("✗ Some tests FAILED!");
        
        $finish;
    end
    
    // =========================================================================
    // Waveform Dump (for GTKWave/ModelSim)
    // =========================================================================
    initial begin
        $dumpfile("knn_classifier_top.vcd");
        $dumpvars(0, tb_knn_classifier_top);
    end
    
    // =========================================================================
    // Monitor Key Signals
    // =========================================================================
    initial begin
        $monitor("[%0t] State: busy=%b, classify_done=%b, result_label=%0d", 
                 $time, busy, classify_done, result_label);
    end

endmodule
