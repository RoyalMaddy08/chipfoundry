module knn_control_unit (
    parameter NUM_SAMPLES = 100,
    parameter NUM_FEATURES = 8,
    parameter K = 5,
    parameter ADDR_WIDTH = 8
)(
    input  wire clk,
    input  wire rst_n,
    
    // =========================================================================
    // External Control Inputs
    // =========================================================================
    input  wire start_classify,        // Start classification process
    input  wire [ADDR_WIDTH-1:0] k_value,  // K value for KNN
    input  wire [ADDR_WIDTH-1:0] num_samples,
    input  wire [$clog2(NUM_FEATURES)-1:0] num_features,
    
    // =========================================================================
    // Status Inputs from Datapath Modules
    // =========================================================================
    input  wire distance_done,         // From distance calculation module
    input  wire sort_done,             // From sort/k-best module
    input  wire majority_done,         // From majority voting module
    input  wire test_sample_loaded,    // Test features loaded into memory
    
    // =========================================================================
    // Control Outputs to Memory
    // =========================================================================
    // Sample feature memory
    output reg  sample_ren,
    output reg  [ADDR_WIDTH-1:0] sample_raddr,
    
    // Sample label memory
    output reg  label_ren,
    output reg  [ADDR_WIDTH-1:0] label_raddr,
    
    // Test sample memory
    output reg  test_ren,
    output reg  [$clog2(NUM_FEATURES)-1:0] test_raddr,
    
    // K-best buffer
    output reg  kbest_ren,
    output reg  [$clog2(NUM_SAMPLES)-1:0] kbest_raddr,
    
    // =========================================================================
    // Control Outputs to Distance Calculation
    // =========================================================================
    output reg  calculate_distance,
    output reg  en_dist_calc,
    output reg  load_test_sample,
    
    // =========================================================================
    // Control Outputs to K-Best Selector (Sort)
    // =========================================================================
    output reg  sort_start,
    output reg  sort_clear,
    output reg  en_sort,
    
    // =========================================================================
    // Control Outputs to Majority Voting
    // =========================================================================
    output reg  majority_start,
    output reg  en_majority_labeling,
    
    // =========================================================================
    // Status Outputs
    // =========================================================================
    output reg  classification_done,
    output reg  [ADDR_WIDTH-1:0] current_sample_idx,
    output reg  [$clog2(NUM_FEATURES)-1:0] current_feature_idx,
    output reg  busy
);

    // =========================================================================
    // FSM State Definition (Based on diagram)
    // =========================================================================
    localparam IDLE                    = 4'd0;
    localparam LOAD_TEST_SAMPLE        = 4'd1;
    localparam STORE_SAMPLE_LABELS     = 4'd2;
    localparam STORE_SAMPLES           = 4'd3;
    localparam LOAD_SAMPLE_FEATURES    = 4'd4;
    localparam CALCULATE_DISTANCE      = 4'd5;
    localparam STORE_DISTANCE          = 4'd6;
    localparam SORT_K_NEAREST          = 4'd7;
    localparam LOAD_FEATURES           = 4'd8;
    localparam MAJORITY_LABELING       = 4'd9;
    localparam STORE_TEST_SAMPLE       = 4'd10;
    localparam OUTPUT_LABEL            = 4'd11;
    
    reg [3:0] state, next_state;
    
    // =========================================================================
    // Internal Counters and Flags
    // =========================================================================
    reg [ADDR_WIDTH-1:0] sample_counter;
    reg [$clog2(NUM_FEATURES)-1:0] feature_counter;
    reg [ADDR_WIDTH-1:0] distance_counter;
    reg [ADDR_WIDTH-1:0] k_counter;
    
    reg update_enable;
    reg classify_enable;
    
    // =========================================================================
    // State Register
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    // =========================================================================
    // Next State Logic
    // =========================================================================
    always @(*) begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (start_classify) begin
                    next_state = LOAD_TEST_SAMPLE;
                end
            end
            
            LOAD_TEST_SAMPLE: begin
                if (test_sample_loaded) begin
                    next_state = STORE_TEST_SAMPLE;
                end
            end
            
            STORE_TEST_SAMPLE: begin
                if (feature_counter >= num_features) begin
                    next_state = LOAD_SAMPLE_FEATURES;
                end
            end
            
            LOAD_SAMPLE_FEATURES: begin
                if (feature_counter >= num_features) begin
                    next_state = CALCULATE_DISTANCE;
                end
            end
            
            CALCULATE_DISTANCE: begin
                if (distance_done) begin
                    next_state = STORE_DISTANCE;
                end
            end
            
            STORE_DISTANCE: begin
                if (sample_counter + 1 >= num_samples) begin
                    next_state = SORT_K_NEAREST;
                end else begin
                    next_state = LOAD_SAMPLE_FEATURES;
                end
            end
            
            SORT_K_NEAREST: begin
                if (sort_done) begin
                    next_state = LOAD_FEATURES;
                end
            end
            
            LOAD_FEATURES: begin
                if (k_counter >= k_value) begin
                    next_state = MAJORITY_LABELING;
                end
            end
            
            MAJORITY_LABELING: begin
                if (majority_done) begin
                    next_state = OUTPUT_LABEL;
                end
            end
            
            OUTPUT_LABEL: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // =========================================================================
    // Output Logic and Datapath Control
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all control signals
            sample_ren <= 0;
            sample_raddr <= 0;
            label_ren <= 0;
            label_raddr <= 0;
            test_ren <= 0;
            test_raddr <= 0;
            kbest_ren <= 0;
            kbest_raddr <= 0;
            
            calculate_distance <= 0;
            en_dist_calc <= 0;
            load_test_sample <= 0;
            
            sort_start <= 0;
            sort_clear <= 0;
            en_sort <= 0;
            
            majority_start <= 0;
            en_majority_labeling <= 0;
            
            classification_done <= 0;
            current_sample_idx <= 0;
            current_feature_idx <= 0;
            busy <= 0;
            
            sample_counter <= 0;
            feature_counter <= 0;
            distance_counter <= 0;
            k_counter <= 0;
            
            update_enable <= 1;
            classify_enable <= 0;
            
        end else begin
            // Default: clear single-cycle pulses
            calculate_distance <= 0;
            sort_start <= 0;
            majority_start <= 0;
            classification_done <= 0;
            
            case (state)
                IDLE: begin
                    busy <= 0;
                    classify_enable <= 0;
                    update_enable <= 1;
                    
                    // Reset counters
                    sample_counter <= 0;
                    feature_counter <= 0;
                    distance_counter <= 0;
                    k_counter <= 0;
                    
                    // Clear all enables
                    en_dist_calc <= 0;
                    en_sort <= 0;
                    en_majority_labeling <= 0;
                    
                    sample_ren <= 0;
                    label_ren <= 0;
                    test_ren <= 0;
                    kbest_ren <= 0;
                    
                    if (start_classify) begin
                        busy <= 1;
                        classify_enable <= 1;
                        update_enable <= 0;
                        load_test_sample <= 1;
                    end
                end
                
                LOAD_TEST_SAMPLE: begin
                    load_test_sample <= 1;
                    test_ren <= 1;
                    
                    if (test_sample_loaded) begin
                        load_test_sample <= 0;
                        feature_counter <= 0;
                    end
                end
                
                STORE_TEST_SAMPLE: begin
                    test_ren <= 1;
                    test_raddr <= feature_counter;
                    current_feature_idx <= feature_counter;
                    
                    if (feature_counter < num_features) begin
                        feature_counter <= feature_counter + 1;
                    end
                end
                
                LOAD_SAMPLE_FEATURES: begin
                    sample_ren <= 1;
                    // Calculate flat address: sample_idx * num_features + feature_idx
                    sample_raddr <= (sample_counter * num_features) + feature_counter;
                    current_sample_idx <= sample_counter;
                    current_feature_idx <= feature_counter;
                    
                    if (feature_counter < num_features) begin
                        feature_counter <= feature_counter + 1;
                    end else begin
                        feature_counter <= 0;
                    end
                end
                
                CALCULATE_DISTANCE: begin
                    en_dist_calc <= 1;
                    calculate_distance <= 1;  // Pulse to start
                    
                    if (distance_done) begin
                        en_dist_calc <= 0;
                    end
                end
                
                STORE_DISTANCE: begin
                    // Distance stored automatically by distance calc module
                    distance_counter <= distance_counter + 1;
                    
                    if (sample_counter + 1 < num_samples) begin
                        sample_counter <= sample_counter + 1;
                        feature_counter <= 0;
                    end else begin
                        sample_counter <= 0;
                    end
                end
                
                SORT_K_NEAREST: begin
                    en_sort <= 1;
                    sort_start <= 1;  // Pulse to start sorting
                    
                    if (sort_done) begin
                        en_sort <= 0;
                        k_counter <= 0;
                    end
                end
                
                LOAD_FEATURES: begin
                    kbest_ren <= 1;
                    kbest_raddr <= k_counter;
                    
                    // Read label for the k-th nearest neighbor
                    label_ren <= 1;
                    label_raddr <= k_counter;
                    
                    if (k_counter < k_value) begin
                        k_counter <= k_counter + 1;
                    end
                end
                
                MAJORITY_LABELING: begin
                    en_majority_labeling <= 1;
                    majority_start <= 1;  // Pulse to start majority voting
                    
                    if (majority_done) begin
                        en_majority_labeling <= 0;
                    end
                end
                
                OUTPUT_LABEL: begin
                    classification_done <= 1;
                    busy <= 0;
                end
                
                default: begin
                    busy <= 0;
                end
            endcase
        end
    end

endmodule
