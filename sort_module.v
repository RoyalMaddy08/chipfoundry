// =============================================================================
// Sort Module: K-Best Selector with Distance Comparison
// =============================================================================
module knn_sort #(
    parameter K = 5,
    parameter NUM_SAMPLES = 100,
    parameter DISTANCE_WIDTH = 32,
    parameter INDEX_WIDTH = 8
)(
    input  wire clk,
    input  wire rst_n,
    
    // =========================================================================
    // Control Interface
    // =========================================================================
    input  wire sort_start,        // Pulse to begin sorting
    input  wire sort_clear,        // Clear k-best buffer
    input  wire en_sort,           // Enable sorting operation
    
    // =========================================================================
    // Distance Stream Input (from distance calculation)
    // =========================================================================
    input  wire dist_valid,
    input  wire [DISTANCE_WIDTH-1:0] dist_data,
    input  wire [INDEX_WIDTH-1:0] dist_index,  // Sample index
    output wire dist_ready,
    
    // =========================================================================
    // K-Best Results Output (to memory for majority voting)
    // =========================================================================
    output reg  kbest_valid,
    output reg  [INDEX_WIDTH-1:0] kbest_index,     // Current output index
    output reg  [DISTANCE_WIDTH-1:0] kbest_distance,
    
    // K-best memory write interface
    output reg  kbest_wen,
    output reg  [$clog2(K)-1:0] kbest_waddr,
    output reg  [INDEX_WIDTH-1:0] kbest_wdata,
    
    // =========================================================================
    // Status Outputs
    // =========================================================================
    output reg  sort_done,
    output reg  [$clog2(K+1)-1:0] num_neighbors  // How many valid neighbors found
);

    // =========================================================================
    // FSM States
    // =========================================================================
    localparam IDLE       = 3'd0;
    localparam ACCEPTING  = 3'd1;
    localparam COMPARE    = 3'd2;
    localparam INSERT     = 3'd3;
    localparam OUTPUT     = 3'd4;
    localparam DONE       = 3'd5;
    
    reg [2:0] state, next_state;
    
    // =========================================================================
    // K-Best Storage Arrays
    // =========================================================================
    reg [DISTANCE_WIDTH-1:0] best_dist [0:K-1];
    reg [INDEX_WIDTH-1:0] best_idx [0:K-1];
    reg [$clog2(K+1)-1:0] valid_count;  // Number of valid entries
    
    // Processing registers
    reg [DISTANCE_WIDTH-1:0] current_dist;
    reg [INDEX_WIDTH-1:0] current_idx;
    reg [$clog2(K)-1:0] insert_pos;
    reg should_insert;
    
    // Sample counter
    reg [INDEX_WIDTH-1:0] samples_processed;
    reg [INDEX_WIDTH-1:0] total_samples;
    
    // Output counter
    reg [$clog2(K)-1:0] output_counter;
    
    // Ready signal: can accept when in ACCEPTING state
    assign dist_ready = (state == ACCEPTING);
    
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
                if (sort_start && en_sort) begin
                    next_state = ACCEPTING;
                end
            end
            
            ACCEPTING: begin
                if (dist_valid && dist_ready) begin
                    next_state = COMPARE;
                end
            end
            
            COMPARE: begin
                if (should_insert) begin
                    next_state = INSERT;
                end else begin
                    // Check if all samples processed
                    if (samples_processed >= total_samples) begin
                        next_state = OUTPUT;
                    end else begin
                        next_state = ACCEPTING;
                    end
                end
            end
            
            INSERT: begin
                // Check if all samples processed
                if (samples_processed >= total_samples) begin
                    next_state = OUTPUT;
                end else begin
                    next_state = ACCEPTING;
                end
            end
            
            OUTPUT: begin
                if (output_counter >= valid_count) begin
                    next_state = DONE;
                end
            end
            
            DONE: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // =========================================================================
    // Datapath Logic
    // =========================================================================
    integer i, j;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all registers
            valid_count <= 0;
            samples_processed <= 0;
            total_samples <= NUM_SAMPLES;
            output_counter <= 0;
            current_dist <= 0;
            current_idx <= 0;
            insert_pos <= 0;
            should_insert <= 0;
            sort_done <= 0;
            kbest_valid <= 0;
            kbest_index <= 0;
            kbest_distance <= 0;
            kbest_wen <= 0;
            kbest_waddr <= 0;
            kbest_wdata <= 0;
            num_neighbors <= 0;
            
            // Initialize k-best arrays to maximum distance
            for (i = 0; i < K; i = i + 1) begin
                best_dist[i] <= {DISTANCE_WIDTH{1'b1}};
                best_idx[i] <= 0;
            end
            
        end else begin
            // Default: clear single-cycle signals
            sort_done <= 0;
            kbest_valid <= 0;
            kbest_wen <= 0;
            
            case (state)
                IDLE: begin
                    valid_count <= 0;
                    samples_processed <= 0;
                    output_counter <= 0;
                    num_neighbors <= 0;
                    
                    if (sort_clear) begin
                        for (i = 0; i < K; i = i + 1) begin
                            best_dist[i] <= {DISTANCE_WIDTH{1'b1}};
                            best_idx[i] <= 0;
                        end
                    end
                    
                    if (sort_start && en_sort) begin
                        total_samples <= NUM_SAMPLES;
                    end
                end
                
                ACCEPTING: begin
                    if (dist_valid && dist_ready) begin
                        // Capture incoming distance and index
                        current_dist <= dist_data;
                        current_idx <= dist_index;
                        samples_processed <= samples_processed + 1;
                    end
                end
                
                COMPARE: begin
                    // Determine if current distance should be inserted
                    should_insert <= 0;
                    insert_pos <= K - 1;
                    
                    // Check if buffer not full or distance is smaller than largest
                    if (valid_count < K) begin
                        should_insert <= 1;
                        // Find insertion position
                        for (i = 0; i < K; i = i + 1) begin
                            if (i < valid_count && current_dist < best_dist[i]) begin
                                insert_pos <= i;
                            end else if (i >= valid_count) begin
                                insert_pos <= i;
                            end
                        end
                    end else if (current_dist < best_dist[K-1]) begin
                        should_insert <= 1;
                        // Find insertion position
                        for (i = 0; i < K; i = i + 1) begin
                            if (current_dist < best_dist[i]) begin
                                insert_pos <= i;
                            end
                        end
                    end
                end
                
                INSERT: begin
                    // Shift elements and insert new distance
                    for (i = K-1; i > 0; i = i - 1) begin
                        if (i > insert_pos) begin
                            best_dist[i] <= best_dist[i-1];
                            best_idx[i] <= best_idx[i-1];
                        end
                    end
                    
                    // Insert new element
                    best_dist[insert_pos] <= current_dist;
                    best_idx[insert_pos] <= current_idx;
                    
                    // Update valid count
                    if (valid_count < K) begin
                        valid_count <= valid_count + 1;
                    end
                end
                
                OUTPUT: begin
                    // Output k-best results one per cycle
                    if (output_counter < valid_count) begin
                        kbest_valid <= 1;
                        kbest_index <= best_idx[output_counter];
                        kbest_distance <= best_dist[output_counter];
                        
                        // Write to k-best memory
                        kbest_wen <= 1;
                        kbest_waddr <= output_counter;
                        kbest_wdata <= best_idx[output_counter];
                        
                        output_counter <= output_counter + 1;
                    end
                    
                    num_neighbors <= valid_count;
                end
                
                DONE: begin
                    sort_done <= 1;
                    num_neighbors <= valid_count;
                end
                
                default: begin
                    // Do nothing
                end
            endcase
        end
    end

endmodule


// =============================================================================
// Majority Voting Module
// =============================================================================
module knn_majority_voting #(
    parameter K = 5,
    parameter NUM_CLASSES = 10,
    parameter LABEL_WIDTH = 4,
    parameter COUNT_WIDTH = 8
)(
    input  wire clk,
    input  wire rst_n,
    
    // =========================================================================
    // Control Interface
    // =========================================================================
    input  wire majority_start,         // Pulse to start voting
    input  wire en_majority_labeling,   // Enable majority voting
    
    // =========================================================================
    // Label Input (from memory via k-best indices)
    // =========================================================================
    input  wire label_valid,
    input  wire [LABEL_WIDTH-1:0] label_data,
    output wire label_ready,
    
    // Alternative: Direct memory read interface
    input  wire [LABEL_WIDTH-1:0] label_rdata_q,
    output reg  label_ren,
    output reg  [$clog2(K)-1:0] label_raddr,
    
    // =========================================================================
    // Configuration
    // =========================================================================
    input  wire [$clog2(K+1)-1:0] k_value,  // Actual K to use
    input  wire [$clog2(NUM_CLASSES)-1:0] num_classes,
    
    // =========================================================================
    // Result Output
    // =========================================================================
    output reg  result_valid,
    output reg  [LABEL_WIDTH-1:0] result_label,
    output reg  [COUNT_WIDTH-1:0] result_count,  // Vote count for winning class
    
    // =========================================================================
    // Status
    // =========================================================================
    output reg  majority_done
);

    // =========================================================================
    // FSM States
    // =========================================================================
    localparam IDLE          = 3'd0;
    localparam LOAD_LABELS   = 3'd1;
    localparam COUNT_VOTES   = 3'd2;
    localparam FIND_MAX      = 3'd3;
    localparam OUTPUT_RESULT = 3'd4;
    
    reg [2:0] state, next_state;
    
    // =========================================================================
    // Vote Counting Arrays
    // =========================================================================
    reg [COUNT_WIDTH-1:0] vote_count [0:NUM_CLASSES-1];
    reg [LABEL_WIDTH-1:0] labels_buffer [0:K-1];
    
    // Processing registers
    reg [$clog2(K)-1:0] label_counter;
    reg [$clog2(NUM_CLASSES)-1:0] class_counter;
    reg [COUNT_WIDTH-1:0] max_votes;
    reg [LABEL_WIDTH-1:0] winning_label;
    
    // Ready signal
    assign label_ready = (state == LOAD_LABELS);
    
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
                if (majority_start && en_majority_labeling) begin
                    next_state = LOAD_LABELS;
                end
            end
            
            LOAD_LABELS: begin
                if (label_counter >= k_value) begin
                    next_state = COUNT_VOTES;
                end
            end
            
            COUNT_VOTES: begin
                if (label_counter >= k_value) begin
                    next_state = FIND_MAX;
                end
            end
            
            FIND_MAX: begin
                if (class_counter >= num_classes) begin
                    next_state = OUTPUT_RESULT;
                end
            end
            
            OUTPUT_RESULT: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // =========================================================================
    // Datapath Logic
    // =========================================================================
    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all registers
            label_counter <= 0;
            class_counter <= 0;
            max_votes <= 0;
            winning_label <= 0;
            result_valid <= 0;
            result_label <= 0;
            result_count <= 0;
            majority_done <= 0;
            label_ren <= 0;
            label_raddr <= 0;
            
            // Clear vote counts
            for (i = 0; i < NUM_CLASSES; i = i + 1) begin
                vote_count[i] <= 0;
            end
            
            // Clear labels buffer
            for (i = 0; i < K; i = i + 1) begin
                labels_buffer[i] <= 0;
            end
            
        end else begin
            // Default: clear single-cycle signals
            result_valid <= 0;
            majority_done <= 0;
            label_ren <= 0;
            
            case (state)
                IDLE: begin
                    label_counter <= 0;
                    class_counter <= 0;
                    max_votes <= 0;
                    winning_label <= 0;
                    
                    // Clear vote counts
                    for (i = 0; i < NUM_CLASSES; i = i + 1) begin
                        vote_count[i] <= 0;
                    end
                    
                    if (majority_start && en_majority_labeling) begin
                        label_ren <= 1;
                        label_raddr <= 0;
                    end
                end
                
                LOAD_LABELS: begin
                    // Read labels from memory (k-best buffer points to sample labels)
                    if (label_counter < k_value) begin
                        label_ren <= 1;
                        label_raddr <= label_counter;
                        
                        // Store label in buffer (one cycle delay for sync read)
                        if (label_counter > 0) begin
                            labels_buffer[label_counter - 1] <= label_rdata_q;
                        end
                        
                        label_counter <= label_counter + 1;
                    end else begin
                        // Store last label
                        labels_buffer[label_counter - 1] <= label_rdata_q;
                        label_counter <= 0;
                    end
                end
                
                COUNT_VOTES: begin
                    // Count votes for each label
                    if (label_counter < k_value) begin
                        // Increment vote count for this label
                        vote_count[labels_buffer[label_counter]] <= 
                            vote_count[labels_buffer[label_counter]] + 1;
                        label_counter <= label_counter + 1;
                    end else begin
                        class_counter <= 0;
                    end
                end
                
                FIND_MAX: begin
                    // Find class with maximum votes
                    if (class_counter < num_classes) begin
                        if (vote_count[class_counter] > max_votes) begin
                            max_votes <= vote_count[class_counter];
                            winning_label <= class_counter;
                        end
                        class_counter <= class_counter + 1;
                    end
                end
                
                OUTPUT_RESULT: begin
                    result_valid <= 1;
                    result_label <= winning_label;
                    result_count <= max_votes;
                    majority_done <= 1;
                end
                
                default: begin
                    // Do nothing
                end
            endcase
        end
    end

endmodule
