module distance_calculation (
    parameter DATA_WIDTH   = 16,
    parameter NUM_FEATURES = 8,
    parameter ADDR_WIDTH   = 8
)(
    input  wire                      clk,
    input  wire                      rst_n,

    // Control signals
    input  wire                      calculate_distance, // start pulse (one clock)
    output reg                       distance_done,      // single-cycle pulse when done

    // Test sample feature input (streamed)
    input  wire [DATA_WIDTH-1:0]     test_feature,
    input  wire                      test_feature_valid, // asserts when test_feature is valid

    // Memory interface for stored samples (read-only)
    output reg  [ADDR_WIDTH-1:0]     sample_feature_addr,
    input  wire [DATA_WIDTH-1:0]     sample_feature_data,

    // Distance output
    output reg  [2*DATA_WIDTH-1:0]   calculated_distance,

    // Distance selection interface
    input  wire                      en_dist_calc,
    output reg                       distance_valid
);

    // FSM States
    localparam IDLE                = 3'd0;
    localparam LOAD_TEST_SAMPLE    = 3'd1;
    localparam LOAD_SAMPLE_ADDR    = 3'd2;
    localparam WAIT_SAMPLE         = 3'd3; // wait one cycle for synchronous BRAM read
    localparam CALCULATE_DISTANCE  = 3'd4;
    localparam STORE_DISTANCE      = 3'd5;

    reg [2:0] state, next_state;

    // Width for feature counters (enough bits for NUM_FEATURES)
    localparam FC_W = (NUM_FEATURES <= 1) ? 1 : $clog2(NUM_FEATURES);

    // Internal registers
    reg [DATA_WIDTH-1:0] test_sample_mem [0:NUM_FEATURES-1];
    reg [DATA_WIDTH-1:0] stored_sample_feature;

    reg [FC_W-1:0] feature_count;      // index for calculating distance (0..NUM_FEATURES-1)
    reg [FC_W-1:0] test_feature_idx;   // index for loading test sample features

    // Accumulators
    reg [2*DATA_WIDTH-1:0] distance_accumulator;
    reg [2*DATA_WIDTH-1:0] diff_squared;

    // signed diff must be declared at module scope
    reg signed [DATA_WIDTH:0] diff; // one extra bit to handle signed subtraction

    // -------------------------------------------------------------------------
    // State register
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // -------------------------------------------------------------------------
    // Next-state logic (combinational)
    // -------------------------------------------------------------------------
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (calculate_distance && en_dist_calc)
                    next_state = LOAD_TEST_SAMPLE;
            end

            LOAD_TEST_SAMPLE: begin
                // stay in this state until all test features are loaded
                if (test_feature_idx == NUM_FEATURES)
                    next_state = LOAD_SAMPLE_ADDR;
            end

            LOAD_SAMPLE_ADDR: begin
                // after presenting address, wait a cycle for synchronous memory read
                next_state = WAIT_SAMPLE;
            end

            WAIT_SAMPLE: begin
                // once data is available, compute distance
                next_state = CALCULATE_DISTANCE;
            end

            CALCULATE_DISTANCE: begin
                // after calculating this feature, either continue reading next sample feature
                // or finish if we've processed NUM_FEATURES features
                if (feature_count + 1 == NUM_FEATURES)
                    next_state = STORE_DISTANCE;
                else
                    next_state = LOAD_SAMPLE_ADDR;
            end

            STORE_DISTANCE: begin
                // produce outputs for one cycle then go to IDLE
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // Datapath & sequential behavior
    // -------------------------------------------------------------------------
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all stateful elements
            distance_done        <= 1'b0;
            distance_valid       <= 1'b0;
            calculated_distance  <= {2*DATA_WIDTH{1'b0}};
            distance_accumulator <= {2*DATA_WIDTH{1'b0}};
            diff_squared         <= {2*DATA_WIDTH{1'b0}};
            feature_count        <= {FC_W{1'b0}};
            test_feature_idx     <= {FC_W{1'b0}};
            sample_feature_addr  <= {ADDR_WIDTH{1'b0}};
            stored_sample_feature<= {DATA_WIDTH{1'b0}};
            diff                 <= {DATA_WIDTH+1{1'b0}};
            // Clear local memory (optional)
            for (i = 0; i < NUM_FEATURES; i = i + 1)
                test_sample_mem[i] <= {DATA_WIDTH{1'b0}};
        end else begin
            // Default: clear single-cycle outputs (they will be asserted explicitly)
            distance_done  <= 1'b0;
            distance_valid <= 1'b0;

            case (state)
                IDLE: begin
                    // prepare registers
                    distance_accumulator <= {2*DATA_WIDTH{1'b0}};
                    calculated_distance  <= {2*DATA_WIDTH{1'b0}};
                    feature_count        <= {FC_W{1'b0}};
                    test_feature_idx     <= {FC_W{1'b0}};
                    sample_feature_addr  <= {ADDR_WIDTH{1'b0}};
                    stored_sample_feature<= {DATA_WIDTH{1'b0}};
                    diff_squared         <= {2*DATA_WIDTH{1'b0}};
                    // if start asserted, next_state logic will move to LOAD_TEST_SAMPLE
                end

                LOAD_TEST_SAMPLE: begin
                    // Expect the test sample features to be provided one-per-clock
                    // together with test_feature_valid asserted.
                    if (test_feature_valid) begin
                        // store incoming test feature into local RAM
                        if (test_feature_idx < NUM_FEATURES) begin
                            test_sample_mem[test_feature_idx] <= test_feature;
                            test_feature_idx <= test_feature_idx + 1'b1;
                        end
                    end
                    // When test_feature_idx reaches NUM_FEATURES, combinational next_state moves on.
                end

                LOAD_SAMPLE_ADDR: begin
                    // Present address of the current feature of the stored sample
                    // Note: sample_feature_data will be valid on next clock for synchronous BRAM/RAM.
                    sample_feature_addr <= sample_feature_addr; // hold current addr (or already set below)
                    // If starting calculation of new sample, ensure sample_feature_addr is initialized appropriately.
                end

                WAIT_SAMPLE: begin
                    // capture the memory data read from sample_feature_addr
                    stored_sample_feature <= sample_feature_data;
                end

                CALCULATE_DISTANCE: begin
                    // compute signed difference between test sample feature and stored sample feature
                    diff <= $signed(test_sample_mem[feature_count]) - $signed(stored_sample_feature);
                    // compute square (will be synthesized as multiplier)
                    diff_squared <= $signed(diff) * $signed(diff);
                    // accumulate
                    distance_accumulator <= distance_accumulator + diff_squared;
                    // increment feature counter
                    feature_count <= feature_count + 1'b1;
                    // increment sample_feature_addr for next feature (preparing next LOAD_SAMPLE_ADDR)
                    sample_feature_addr <= sample_feature_addr + 1'b1;
                end

                STORE_DISTANCE: begin
                    // Finalize and present results for one cycle
                    calculated_distance <= distance_accumulator;
                    distance_valid      <= 1'b1;
                    distance_done       <= 1'b1;
                    // NB: stay in next_state = IDLE next cycle
                end

                default: begin
                    // nothing special
                end
            endcase
        end
    end

endmodule
