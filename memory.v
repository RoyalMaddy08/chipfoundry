module knn_memory (
    parameter DATA_WIDTH = 16,
    parameter NUM_FEATURES = 8,
    parameter NUM_SAMPLES = 100,
    parameter LABEL_WIDTH = 4,
    parameter ADDR_WIDTH = 8
)(
    input  wire clk,
    input  wire rst_n,
    
    // =========================================================================
    // Sample Feature Memory Interface (Training Data)
    // =========================================================================
    // Write port
    input  wire sample_wen,
    input  wire [ADDR_WIDTH-1:0] sample_waddr,
    input  wire [DATA_WIDTH-1:0] sample_wdata,
    
    // Read port
    input  wire sample_ren,
    input  wire [ADDR_WIDTH-1:0] sample_raddr,
    output reg  [DATA_WIDTH-1:0] sample_rdata_q,
    
    // =========================================================================
    // Sample Label Memory Interface (Training Labels)
    // =========================================================================
    // Write port
    input  wire label_wen,
    input  wire [ADDR_WIDTH-1:0] label_waddr,
    input  wire [LABEL_WIDTH-1:0] label_wdata,
    
    // Read port
    input  wire label_ren,
    input  wire [ADDR_WIDTH-1:0] label_raddr,
    output reg  [LABEL_WIDTH-1:0] label_rdata_q,
    
    // =========================================================================
    // Test Sample Memory Interface
    // =========================================================================
    // Write port
    input  wire test_wen,
    input  wire [$clog2(NUM_FEATURES)-1:0] test_waddr,
    input  wire [DATA_WIDTH-1:0] test_wdata,
    
    // Read port
    input  wire test_ren,
    input  wire [$clog2(NUM_FEATURES)-1:0] test_raddr,
    output reg  [DATA_WIDTH-1:0] test_rdata_q,
    
    // =========================================================================
    // K-Best Buffer Interface (for sorted nearest neighbors)
    // =========================================================================
    // Write port (from K-best selector module)
    input  wire kbest_wen,
    input  wire [$clog2(NUM_SAMPLES)-1:0] kbest_waddr,
    input  wire [ADDR_WIDTH-1:0] kbest_wdata,  // sample index
    
    // Read port (for majority voting)
    input  wire kbest_ren,
    input  wire [$clog2(NUM_SAMPLES)-1:0] kbest_raddr,
    output reg  [ADDR_WIDTH-1:0] kbest_rdata_q,
    
    // =========================================================================
    // Configuration and Status
    // =========================================================================
    input  wire [ADDR_WIDTH-1:0] cfg_num_samples,
    input  wire [$clog2(NUM_FEATURES)-1:0] cfg_num_features,
    
    output reg  [ADDR_WIDTH-1:0] sample_count,
    output reg  [$clog2(NUM_FEATURES)-1:0] feature_count
);

    // =========================================================================
    // Memory Arrays - All synchronous read/write
    // =========================================================================
    
    // Sample feature memory: [sample_idx * NUM_FEATURES + feature_idx]
    // Organized as flattened 2D array
    reg [DATA_WIDTH-1:0] sample_feature_mem [0:NUM_SAMPLES*NUM_FEATURES-1];
    
    // Sample label memory: ground truth labels for training samples
    reg [LABEL_WIDTH-1:0] sample_label_mem [0:NUM_SAMPLES-1];
    
    // Test sample memory: features of the current test vector
    reg [DATA_WIDTH-1:0] test_sample_mem [0:NUM_FEATURES-1];
    
    // K-best buffer: indices of K nearest neighbor samples
    reg [ADDR_WIDTH-1:0] kbest_buffer [0:NUM_SAMPLES-1];
    
    // =========================================================================
    // Sample Feature Memory - Synchronous Read/Write
    // =========================================================================
    always @(posedge clk) begin
        if (sample_wen) begin
            sample_feature_mem[sample_waddr] <= sample_wdata;
        end
        
        if (sample_ren) begin
            sample_rdata_q <= sample_feature_mem[sample_raddr];
        end
    end
    
    // =========================================================================
    // Sample Label Memory - Synchronous Read/Write
    // =========================================================================
    always @(posedge clk) begin
        if (label_wen) begin
            sample_label_mem[label_waddr] <= label_wdata;
        end
        
        if (label_ren) begin
            label_rdata_q <= sample_label_mem[label_raddr];
        end
    end
    
    // =========================================================================
    // Test Sample Memory - Synchronous Read/Write
    // =========================================================================
    always @(posedge clk) begin
        if (test_wen) begin
            test_sample_mem[test_waddr] <= test_wdata;
        end
        
        if (test_ren) begin
            test_rdata_q <= test_sample_mem[test_raddr];
        end
    end
    
    // =========================================================================
    // K-Best Buffer - Synchronous Read/Write
    // =========================================================================
    always @(posedge clk) begin
        if (kbest_wen) begin
            kbest_buffer[kbest_waddr] <= kbest_wdata;
        end
        
        if (kbest_ren) begin
            kbest_rdata_q <= kbest_buffer[kbest_raddr];
        end
    end
    
    // =========================================================================
    // Counter Management
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_count <= 0;
            feature_count <= 0;
        end else begin
            // Update counts from configuration
            sample_count <= cfg_num_samples;
            feature_count <= cfg_num_features;
        end
    end
    
    // =========================================================================
    // Memory Initialization (Optional - for simulation)
    // =========================================================================
    integer i;
    initial begin
        for (i = 0; i < NUM_SAMPLES*NUM_FEATURES; i = i + 1)
            sample_feature_mem[i] = 0;
        
        for (i = 0; i < NUM_SAMPLES; i = i + 1) begin
            sample_label_mem[i] = 0;
            kbest_buffer[i] = 0;
        end
        
        for (i = 0; i < NUM_FEATURES; i = i + 1)
            test_sample_mem[i] = 0;
    end

endmodule


// =============================================================================
// K-Best Selector Module (Separate from memory)
// =============================================================================
module kbest_selector #(
    parameter K = 5,
    parameter NUM_SAMPLES = 100,
    parameter DISTANCE_WIDTH = 32,
    parameter INDEX_WIDTH = 8
)(
    input  wire clk,
    input  wire rst_n,
    
    // Control
    input  wire start,          // pulse to begin new classification
    input  wire clear,          // clear current k-best list
    
    // Distance stream input
    input  wire dist_valid,
    input  wire [DISTANCE_WIDTH-1:0] dist_data,
    input  wire [INDEX_WIDTH-1:0] dist_index,  // sample index
    output wire dist_ready,
    
    // K-best output (after all samples processed)
    output reg  kbest_valid,
    output reg  [INDEX_WIDTH-1:0] kbest_indices [0:K-1],
    output reg  [DISTANCE_WIDTH-1:0] kbest_distances [0:K-1],
    
    // Status
    output reg  done
);

    // K-best buffer: maintain K smallest distances and their indices
    reg [DISTANCE_WIDTH-1:0] best_dist [0:K-1];
    reg [INDEX_WIDTH-1:0] best_idx [0:K-1];
    reg [$clog2(K+1)-1:0] count;  // how many valid entries in buffer
    
    reg [$clog2(NUM_SAMPLES+1)-1:0] samples_processed;
    
    // FSM states
    localparam IDLE = 2'd0;
    localparam ACCEPTING = 2'd1;
    localparam DONE = 2'd2;
    
    reg [1:0] state;
    
    // Ready to accept new distance when in ACCEPTING state
    assign dist_ready = (state == ACCEPTING);
    
    integer i, j;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            count <= 0;
            samples_processed <= 0;
            done <= 0;
            kbest_valid <= 0;
            
            for (i = 0; i < K; i = i + 1) begin
                best_dist[i] <= {DISTANCE_WIDTH{1'b1}};  // Max value
                best_idx[i] <= 0;
                kbest_indices[i] <= 0;
                kbest_distances[i] <= 0;
            end
            
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    kbest_valid <= 0;
                    samples_processed <= 0;
                    
                    if (start || clear) begin
                        count <= 0;
                        for (i = 0; i < K; i = i + 1) begin
                            best_dist[i] <= {DISTANCE_WIDTH{1'b1}};
                            best_idx[i] <= 0;
                        end
                    end
                    
                    if (start) begin
                        state <= ACCEPTING;
                    end
                end
                
                ACCEPTING: begin
                    if (dist_valid && dist_ready) begin
                        // Compare-and-insert new distance into k-best list
                        // Check if distance is smaller than largest in buffer
                        if (count < K || dist_data < best_dist[K-1]) begin
                            // Find insertion position
                            for (i = 0; i < K; i = i + 1) begin
                                if (dist_data < best_dist[i]) begin
                                    // Shift larger elements right
                                    for (j = K-1; j > i; j = j - 1) begin
                                        best_dist[j] <= best_dist[j-1];
                                        best_idx[j] <= best_idx[j-1];
                                    end
                                    // Insert new element
                                    best_dist[i] <= dist_data;
                                    best_idx[i] <= dist_index;
                                    
                                    // Update count if buffer not full
                                    if (count < K)
                                        count <= count + 1;
                                    
                                    // Break the loop (synthesis-friendly way)
                                    i = K;
                                end
                            end
                        end
                        
                        samples_processed <= samples_processed + 1;
                        
                        // Check if all samples processed
                        if (samples_processed + 1 >= NUM_SAMPLES) begin
                            state <= DONE;
                        end
                    end
                end
                
                DONE: begin
                    done <= 1;
                    kbest_valid <= 1;
                    
                    // Output k-best results
                    for (i = 0; i < K; i = i + 1) begin
                        kbest_indices[i] <= best_idx[i];
                        kbest_distances[i] <= best_dist[i];
                    end
                    
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
