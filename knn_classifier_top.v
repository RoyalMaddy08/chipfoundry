// =============================================================================
// Top-Level KNN Classifier - Integrates All Modules
// =============================================================================
module knn_classifier_top (
    parameter DATA_WIDTH = 16,
    parameter NUM_FEATURES = 8,
    parameter NUM_SAMPLES = 100,
    parameter LABEL_WIDTH = 4,
    parameter NUM_CLASSES = 10,
    parameter ADDR_WIDTH = 8,
    parameter DISTANCE_WIDTH = 32,
    parameter K = 5
)(
    input  wire clk,
    input  wire rst_n,
    
    // =========================================================================
    // External Interface - Training Data Loading
    // =========================================================================
    input  wire train_mode,                     // Training mode enable
    input  wire train_sample_wen,               // Write enable for training samples
    input  wire [ADDR_WIDTH-1:0] train_sample_addr,
    input  wire [DATA_WIDTH-1:0] train_sample_data,
    
    input  wire train_label_wen,                // Write enable for training labels
    input  wire [ADDR_WIDTH-1:0] train_label_addr,
    input  wire [LABEL_WIDTH-1:0] train_label_data,
    
    // =========================================================================
    // External Interface - Test/Classification
    // =========================================================================
    input  wire classify_start,                 // Start classification
    input  wire test_feature_valid,             // Test feature input valid
    input  wire [DATA_WIDTH-1:0] test_feature_data,
    
    // =========================================================================
    // Configuration
    // =========================================================================
    input  wire [ADDR_WIDTH-1:0] cfg_num_samples,
    input  wire [$clog2(NUM_FEATURES)-1:0] cfg_num_features,
    input  wire [$clog2(K+1)-1:0] cfg_k_value,
    
    // =========================================================================
    // Output Interface
    // =========================================================================
    output wire classify_done,
    output wire [LABEL_WIDTH-1:0] result_label,
    output wire [$clog2(K+1)-1:0] result_confidence,
    output wire busy
);

    // =========================================================================
    // Internal Wires - Control Unit to Memory
    // =========================================================================
    wire sample_ren;
    wire [ADDR_WIDTH-1:0] sample_raddr;
    wire label_ren;
    wire [ADDR_WIDTH-1:0] label_raddr;
    wire test_ren;
    wire [$clog2(NUM_FEATURES)-1:0] test_raddr;
    wire kbest_ren;
    wire [$clog2(NUM_SAMPLES)-1:0] kbest_raddr;
    
    // =========================================================================
    // Internal Wires - Memory Outputs
    // =========================================================================
    wire [DATA_WIDTH-1:0] sample_rdata_q;
    wire [LABEL_WIDTH-1:0] label_rdata_q;
    wire [DATA_WIDTH-1:0] test_rdata_q;
    wire [ADDR_WIDTH-1:0] kbest_rdata_q;
    
    // =========================================================================
    // Internal Wires - Control Unit to Distance Calculation
    // =========================================================================
    wire calculate_distance;
    wire en_dist_calc;
    wire load_test_sample;
    
    // =========================================================================
    // Internal Wires - Distance Calculation Module
    // =========================================================================
    wire distance_done;
    wire distance_valid;
    wire [DISTANCE_WIDTH-1:0] calculated_distance;
    wire [ADDR_WIDTH-1:0] dist_calc_sample_addr;
    wire [$clog2(NUM_FEATURES)-1:0] dist_calc_test_addr;
    
    // =========================================================================
    // Internal Wires - Control Unit to Sort
    // =========================================================================
    wire sort_start;
    wire sort_clear;
    wire en_sort;
    
    // =========================================================================
    // Internal Wires - Sort Module
    // =========================================================================
    wire sort_done;
    wire dist_ready;
    wire kbest_valid;
    wire [ADDR_WIDTH-1:0] kbest_index;
    wire [DISTANCE_WIDTH-1:0] kbest_distance;
    wire kbest_wen;
    wire [$clog2(K)-1:0] kbest_waddr;
    wire [ADDR_WIDTH-1:0] kbest_wdata;
    wire [$clog2(K+1)-1:0] num_neighbors;
    
    // =========================================================================
    // Internal Wires - Control Unit to Majority Voting
    // =========================================================================
    wire majority_start;
    wire en_majority_labeling;
    
    // =========================================================================
    // Internal Wires - Majority Voting Module
    // =========================================================================
    wire majority_done;
    wire result_valid;
    wire [LABEL_WIDTH-1:0] majority_result_label;
    wire [7:0] majority_result_count;
    wire majority_label_ren;
    wire [$clog2(K)-1:0] majority_label_raddr;
    
    // =========================================================================
    // Internal Wires - Status
    // =========================================================================
    wire [ADDR_WIDTH-1:0] current_sample_idx;
    wire [$clog2(NUM_FEATURES)-1:0] current_feature_idx;
    wire test_sample_loaded;
    
    // =========================================================================
    // Memory Write Control - Mux between training and internal operations
    // =========================================================================
    wire sample_wen_internal;
    wire [ADDR_WIDTH-1:0] sample_waddr_internal;
    wire [DATA_WIDTH-1:0] sample_wdata_internal;
    
    wire label_wen_internal;
    wire [ADDR_WIDTH-1:0] label_waddr_internal;
    wire [LABEL_WIDTH-1:0] label_wdata_internal;
    
    wire test_wen_internal;
    wire [$clog2(NUM_FEATURES)-1:0] test_waddr_internal;
    wire [DATA_WIDTH-1:0] test_wdata_internal;
    
    // Mux: training mode uses external signals, else internal
    wire sample_wen_mux = train_mode ? train_sample_wen : sample_wen_internal;
    wire [ADDR_WIDTH-1:0] sample_waddr_mux = train_mode ? train_sample_addr : sample_waddr_internal;
    wire [DATA_WIDTH-1:0] sample_wdata_mux = train_mode ? train_sample_data : sample_wdata_internal;
    
    wire label_wen_mux = train_mode ? train_label_wen : label_wen_internal;
    wire [ADDR_WIDTH-1:0] label_waddr_mux = train_mode ? train_label_addr : label_waddr_internal;
    wire [LABEL_WIDTH-1:0] label_wdata_mux = train_mode ? train_label_data : label_wdata_internal;
    
    // Test sample written during classification
    assign test_wen_internal = test_feature_valid && load_test_sample;
    assign test_waddr_internal = current_feature_idx;
    assign test_wdata_internal = test_feature_data;
    
    // Test sample loaded when all features received
    assign test_sample_loaded = (current_feature_idx >= cfg_num_features) && load_test_sample;
    
    // =========================================================================
    // Output Assignments
    // =========================================================================
    assign classify_done = majority_done;
    assign result_label = majority_result_label;
    assign result_confidence = majority_result_count;
    
    // =========================================================================
    // Module Instantiations
    // =========================================================================
    
    // -------------------------------------------------------------------------
    // Control Unit
    // -------------------------------------------------------------------------
    knn_control_unit #(
        .NUM_SAMPLES(NUM_SAMPLES),
        .NUM_FEATURES(NUM_FEATURES),
        .K(K),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) control_unit_inst (
        .clk(clk),
        .rst_n(rst_n),
        
        // External control
        .start_classify(classify_start && !train_mode),
        .k_value(cfg_k_value),
        .num_samples(cfg_num_samples),
        .num_features(cfg_num_features),
        
        // Status inputs
        .distance_done(distance_done),
        .sort_done(sort_done),
        .majority_done(majority_done),
        .test_sample_loaded(test_sample_loaded),
        
        // Memory control outputs
        .sample_ren(sample_ren),
        .sample_raddr(sample_raddr),
        .label_ren(label_ren),
        .label_raddr(label_raddr),
        .test_ren(test_ren),
        .test_raddr(test_raddr),
        .kbest_ren(kbest_ren),
        .kbest_raddr(kbest_raddr),
        
        // Distance calculation control
        .calculate_distance(calculate_distance),
        .en_dist_calc(en_dist_calc),
        .load_test_sample(load_test_sample),
        
        // Sort control
        .sort_start(sort_start),
        .sort_clear(sort_clear),
        .en_sort(en_sort),
        
        // Majority voting control
        .majority_start(majority_start),
        .en_majority_labeling(en_majority_labeling),
        
        // Status outputs
        .classification_done(),
        .current_sample_idx(current_sample_idx),
        .current_feature_idx(current_feature_idx),
        .busy(busy)
    );
    
    // -------------------------------------------------------------------------
    // Memory Block
    // -------------------------------------------------------------------------
    knn_memory #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_FEATURES(NUM_FEATURES),
        .NUM_SAMPLES(NUM_SAMPLES),
        .LABEL_WIDTH(LABEL_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) memory_inst (
        .clk(clk),
        .rst_n(rst_n),
        
        // Sample feature memory
        .sample_wen(sample_wen_mux),
        .sample_waddr(sample_waddr_mux),
        .sample_wdata(sample_wdata_mux),
        .sample_ren(sample_ren),
        .sample_raddr(sample_raddr),
        .sample_rdata_q(sample_rdata_q),
        
        // Sample label memory
        .label_wen(label_wen_mux),
        .label_waddr(label_waddr_mux),
        .label_wdata(label_wdata_mux),
        .label_ren(label_ren),
        .label_raddr(label_raddr),
        .label_rdata_q(label_rdata_q),
        
        // Test sample memory
        .test_wen(test_wen_internal),
        .test_waddr(test_waddr_internal),
        .test_wdata(test_wdata_internal),
        .test_ren(test_ren),
        .test_raddr(test_raddr),
        .test_rdata_q(test_rdata_q),
        
        // K-best buffer
        .kbest_wen(kbest_wen),
        .kbest_waddr(kbest_waddr),
        .kbest_wdata(kbest_wdata),
        .kbest_ren(kbest_ren),
        .kbest_raddr(kbest_raddr),
        .kbest_rdata_q(kbest_rdata_q),
        
        // Configuration
        .cfg_num_samples(cfg_num_samples),
        .cfg_num_features(cfg_num_features),
        .sample_count(),
        .feature_count()
    );
    
    // -------------------------------------------------------------------------
    // Distance Calculation Module
    // -------------------------------------------------------------------------
    distance_calculation #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_FEATURES(NUM_FEATURES),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) distance_calc_inst (
        .clk(clk),
        .rst_n(rst_n),
        
        // Control
        .calculate_distance(calculate_distance),
        .distance_done(distance_done),
        
        // Test sample input (streamed during load phase)
        .test_feature(test_feature_data),
        .test_feature_valid(test_feature_valid && load_test_sample),
        
        // Memory interface for stored samples
        .sample_feature_addr(dist_calc_sample_addr),
        .sample_feature_data(sample_rdata_q),
        
        // Distance output
        .calculated_distance(calculated_distance),
        
        // Control
        .en_dist_calc(en_dist_calc),
        .distance_valid(distance_valid)
    );
    
    // Distance calculation uses control unit's sample address
    assign dist_calc_sample_addr = sample_raddr;
    
    // -------------------------------------------------------------------------
    // Sort Module (K-Best Selector)
    // -------------------------------------------------------------------------
    knn_sort #(
        .K(K),
        .NUM_SAMPLES(NUM_SAMPLES),
        .DISTANCE_WIDTH(DISTANCE_WIDTH),
        .INDEX_WIDTH(ADDR_WIDTH)
    ) sort_inst (
        .clk(clk),
        .rst_n(rst_n),
        
        // Control
        .sort_start(sort_start),
        .sort_clear(sort_clear),
        .en_sort(en_sort),
        
        // Distance stream input
        .dist_valid(distance_valid && en_sort),
        .dist_data(calculated_distance),
        .dist_index(current_sample_idx),
        .dist_ready(dist_ready),
        
        // K-best results
        .kbest_valid(kbest_valid),
        .kbest_index(kbest_index),
        .kbest_distance(kbest_distance),
        
        // Memory write interface
        .kbest_wen(kbest_wen),
        .kbest_waddr(kbest_waddr),
        .kbest_wdata(kbest_wdata),
        
        // Status
        .sort_done(sort_done),
        .num_neighbors(num_neighbors)
    );
    
    // -------------------------------------------------------------------------
    // Majority Voting Module
    // -------------------------------------------------------------------------
    knn_majority_voting #(
        .K(K),
        .NUM_CLASSES(NUM_CLASSES),
        .LABEL_WIDTH(LABEL_WIDTH),
        .COUNT_WIDTH(8)
    ) majority_voting_inst (
        .clk(clk),
        .rst_n(rst_n),
        
        // Control
        .majority_start(majority_start),
        .en_majority_labeling(en_majority_labeling),
        
        // Label input (streaming mode - not used in this config)
        .label_valid(1'b0),
        .label_data({LABEL_WIDTH{1'b0}}),
        .label_ready(),
        
        // Memory read interface
        .label_rdata_q(label_rdata_q),
        .label_ren(majority_label_ren),
        .label_raddr(majority_label_raddr),
        
        // Configuration
        .k_value(cfg_k_value),
        .num_classes(NUM_CLASSES),
        
        // Result output
        .result_valid(result_valid),
        .result_label(majority_result_label),
        .result_count(majority_result_count),
        
        // Status
        .majority_done(majority_done)
    );
    
    // NOTE: Majority voting needs to read labels of K-best samples
    // This requires an additional level of indirection:
    // 1. Read k-best buffer to get sample indices
    // 2. Use those indices to read actual labels
    // For now, simplified to direct label access
    
    // Internal signals (currently unused in basic config)
    assign sample_wen_internal = 1'b0;
    assign sample_waddr_internal = {ADDR_WIDTH{1'b0}};
    assign sample_wdata_internal = {DATA_WIDTH{1'b0}};
    assign label_wen_internal = 1'b0;
    assign label_waddr_internal = {ADDR_WIDTH{1'b0}};
    assign label_wdata_internal = {LABEL_WIDTH{1'b0}};

endmodule
