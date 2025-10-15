`timescale 1ns/1ps

module tb_knn_verilog;

  // Parameters
  localparam DATA_WIDTH = 16;
  localparam NUM_FEATURES = 4;
  localparam NUM_SAMPLES = 16;
  localparam LABEL_WIDTH = 3;
  localparam ADDR_WIDTH = 4;
  localparam K = 5;
  localparam DIST_W = 32;
  localparam CLK_PER = 10;

  // Clock/Reset
  reg clk, rst_n;

  // knn_memory IF
  reg sample_wen;
  reg [ADDR_WIDTH-1:0] sample_waddr;
  reg [DATA_WIDTH-1:0] sample_wdata;

  reg sample_ren;
  reg [ADDR_WIDTH-1:0] sample_raddr;
  wire [DATA_WIDTH-1:0] sample_rdata_q;

  reg label_wen;
  reg [ADDR_WIDTH-1:0] label_waddr;
  reg [LABEL_WIDTH-1:0] label_wdata;

  reg label_ren;
  reg [ADDR_WIDTH-1:0] label_raddr;
  wire [LABEL_WIDTH-1:0] label_rdata_q;

  reg test_wen;
  reg [clog2_int(NUM_FEATURES)-1:0] test_waddr;
  reg [DATA_WIDTH-1:0] test_wdata;

  reg test_ren;
  reg [clog2_int(NUM_FEATURES)-1:0] test_raddr;
  wire [DATA_WIDTH-1:0] test_rdata_q;

  reg kbest_wen;
  reg [clog2_int(NUM_SAMPLES)-1:0] kbest_waddr;
  reg [ADDR_WIDTH-1:0] kbest_wdata;

  reg kbest_ren;
  reg [clog2_int(NUM_SAMPLES)-1:0] kbest_raddr;
  wire [ADDR_WIDTH-1:0] kbest_rdata_q;

  reg [ADDR_WIDTH-1:0] cfg_num_samples;
  reg [clog2_int(NUM_FEATURES)-1:0] cfg_num_features;
  wire [ADDR_WIDTH-1:0] sample_count;
  wire [clog2_int(NUM_FEATURES)-1:0] feature_count;

  // kbest_selector wrap IF
  reg start, clear;
  reg dist_valid;
  reg [DIST_W-1:0] dist_data;
  reg [ADDR_WIDTH-1:0] dist_index;
  wire dist_ready;

  wire done;
  wire kbest_valid;
  wire [K*ADDR_WIDTH-1:0] kbest_indices_bus;
  wire [K*DIST_W-1:0] kbest_distances_bus;

  // Clock
  initial clk = 1'b0;
  always #(CLK_PER/2) clk = ~clk;

  // CLOG2 for params (Verilog function)
  function integer clog2_int;
    input integer value;
    integer i;
    begin
      clog2_int = 0;
      for (i = value-1; i > 0; i = i >> 1)
        clog2_int = clog2_int + 1;
    end
  endfunction

  // Address calc
  function [ADDR_WIDTH-1:0] feat_addr;
    input integer s;
    input integer f;
    integer flat;
    begin
      flat = s*NUM_FEATURES + f;
      feat_addr = flat[ADDR_WIDTH-1:0];
    end
  endfunction

  // DUT: memory
  knn_memory #(
    .DATA_WIDTH(DATA_WIDTH),
    .NUM_FEATURES(NUM_FEATURES),
    .NUM_SAMPLES(NUM_SAMPLES),
    .LABEL_WIDTH(LABEL_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
  ) u_mem (
    .clk(clk), .rst_n(rst_n),
    .sample_wen(sample_wen), .sample_waddr(sample_waddr), .sample_wdata(sample_wdata),
    .sample_ren(sample_ren), .sample_raddr(sample_raddr), .sample_rdata_q(sample_rdata_q),
    .label_wen(label_wen), .label_waddr(label_waddr), .label_wdata(label_wdata),
    .label_ren(label_ren), .label_raddr(label_raddr), .label_rdata_q(label_rdata_q),
    .test_wen(test_wen), .test_waddr(test_waddr), .test_wdata(test_wdata),
    .test_ren(test_ren), .test_raddr(test_raddr), .test_rdata_q(test_rdata_q),
    .kbest_wen(kbest_wen), .kbest_waddr(kbest_waddr), .kbest_wdata(kbest_wdata),
    .kbest_ren(kbest_ren), .kbest_raddr(kbest_raddr), .kbest_rdata_q(kbest_rdata_q),
    .cfg_num_samples(cfg_num_samples), .cfg_num_features(cfg_num_features),
    .sample_count(sample_count), .feature_count(feature_count)
  );

  // DUT: selector wrapper (plain Verilog compatible)
  kbest_selector_wrap #(
    .K(K),
    .NUM_SAMPLES(NUM_SAMPLES),
    .DISTANCE_WIDTH(DIST_W),
    .INDEX_WIDTH(ADDR_WIDTH)
  ) u_selw (
    .clk(clk), .rst_n(rst_n),
    .start(start), .clear(clear),
    .dist_valid(dist_valid), .dist_data(dist_data), .dist_index(dist_index),
    .dist_ready(dist_ready),
    .kbest_valid(kbest_valid),
    .kbest_indices_bus(kbest_indices_bus),
    .kbest_distances_bus(kbest_distances_bus),
    .done(done)
  );

  // Reset
  task do_reset;
    begin
      rst_n = 0;
      sample_wen = 0; sample_ren = 0;
      label_wen = 0; label_ren = 0;
      test_wen = 0; test_ren = 0;
      kbest_wen = 0; kbest_ren = 0;
      start = 0; clear = 0; dist_valid = 0; dist_data = 0; dist_index = 0;
      cfg_num_samples = NUM_SAMPLES[ADDR_WIDTH-1:0];
      cfg_num_features = NUM_FEATURES[clog2_int(NUM_FEATURES)-1:0];
      repeat (5) @(posedge clk);
      rst_n = 1;
      @(posedge clk);
    end
  endtask

  // Write training set
  task write_training;
    integer s,f;
    begin
      for (s = 0; s < NUM_SAMPLES; s = s + 1) begin
        // label
        @(posedge clk);
        label_wen <= 1'b1;
        label_waddr <= s[ADDR_WIDTH-1:0];
        label_wdata <= (s % 6)[LABEL_WIDTH-1:0];
        // features
        for (f = 0; f < NUM_FEATURES; f = f + 1) begin
          @(posedge clk);
          sample_wen <= 1'b1;
          sample_waddr <= feat_addr(s,f);
          sample_wdata <= (10*s + f)[DATA_WIDTH-1:0];
        end
        @(posedge clk);
        label_wen <= 1'b0;
        sample_wen <= 1'b0;
      end
    end
  endtask

  // Write test vector
  task write_test;
    integer f;
    begin
      for (f = 0; f < NUM_FEATURES; f = f + 1) begin
        @(posedge clk);
        test_wen <= 1'b1;
        test_waddr <= f[clog2_int(NUM_FEATURES)-1:0];
        test_wdata <= (100 + f)[DATA_WIDTH-1:0];
      end
      @(posedge clk);
      test_wen <= 1'b0;
    end
  endtask

  // Readback spot checks
  task readback_checks;
    integer s,f,exp;
    begin
      s = 7; f = 3;
      // feature
      @(posedge clk);
      sample_ren <= 1'b1;
      sample_raddr <= feat_addr(s,f);
      @(posedge clk);
      sample_ren <= 1'b0;
      exp = 10*s + f;
      if (sample_rdata_q !== exp[DATA_WIDTH-1:0]) begin
        $display("ERROR: feature mismatch s=%0d f=%0d exp=%0d got=%0d",
                  s,f,exp,sample_rdata_q);
        $finish;
      end
      // label
      @(posedge clk);
      label_ren <= 1'b1;
      label_raddr <= s[ADDR_WIDTH-1:0];
      @(posedge clk);
      label_ren <= 1'b0;
      exp = (s % 6);
      if (label_rdata_q !== exp[LABEL_WIDTH-1:0]) begin
        $display("ERROR: label mismatch s=%0d exp=%0d got=%0d",
                  s,exp,label_rdata_q);
        $finish;
      end
      // test vector element f=2
      f = 2;
      @(posedge clk);
      test_ren <= 1'b1;
      test_raddr <= f[clog2_int(NUM_FEATURES)-1:0];
      @(posedge clk);
      test_ren <= 1'b0;
      exp = 100 + f;
      if (test_rdata_q !== exp[DATA_WIDTH-1:0]) begin
        $display("ERROR: test mismatch f=%0d exp=%0d got=%0d",
                 f,exp,test_rdata_q);
        $finish;
      end
    end
  endtask

  // Stream distances to selector; distance = |10*s - 105|
  task run_kbest_and_buffer;
    integer s;
    integer dist;
    integer i;
    reg [ADDR_WIDTH-1:0] idx_i;
    reg [DIST_W-1:0] dis_i;
    begin
      // clear
      @(posedge clk); clear <= 1'b1;
      @(posedge clk); clear <= 1'b0;

      // start
      @(posedge clk); start <= 1'b1;
      @(posedge clk); start <= 1'b0;

      for (s = 0; s < NUM_SAMPLES; s = s + 1) begin
        dist = (10*s > 105) ? (10*s - 105) : (105 - 10*s);
        // wait ready
        @(posedge clk);
        while (!dist_ready) @(posedge clk);
        dist_valid <= 1'b1;
        dist_data <= dist[DIST_W-1:0];
        dist_index <= s[ADDR_WIDTH-1:0];
        @(posedge clk);
        dist_valid <= 1'b0;
      end

      // wait done
      wait(done == 1'b1);
      @(posedge clk);
      if (kbest_valid !== 1'b1) begin
        $display("ERROR: kbest_valid not high at DONE");
        $finish;
      end

      // mirror into memory buffer
      for (i = 0; i < K; i = i + 1) begin
        idx_i = kbest_indices_bus[ (i+1)*ADDR_WIDTH-1 : i*ADDR_WIDTH ];
        @(posedge clk);
        kbest_wen <= 1'b1;
        kbest_waddr <= i[clog2_int(NUM_SAMPLES)-1:0];
        kbest_wdata <= idx_i;
      end
      @(posedge clk);
      kbest_wen <= 1'b0;

      // readback verify
      for (i = 0; i < K; i = i + 1) begin
        idx_i = kbest_indices_bus[ (i+1)*ADDR_WIDTH-1 : i*ADDR_WIDTH ];
        @(posedge clk);
        kbest_ren <= 1'b1;
        kbest_raddr <= i[clog2_int(NUM_SAMPLES)-1:0];
        @(posedge clk);
        kbest_ren <= 1'b0;
        if (kbest_rdata_q !== idx_i) begin
          $display("ERROR: kbest buffer mismatch at %0d exp=%0d got=%0d",
                   i, idx_i, kbest_rdata_q);
          $finish;
        end
      end

      // print results
      $display("K-best (index:distance)");
      for (i = 0; i < K; i = i + 1) begin
        idx_i = kbest_indices_bus[ (i+1)*ADDR_WIDTH-1 : i*ADDR_WIDTH ];
        dis_i = kbest_distances_bus[ (i+1)*DIST_W-1 : i*DIST_W ];
        $display(" %0d : %0d", idx_i, dis_i);
      end
    end
  endtask

  // Test sequence
  initial begin
    do_reset();
    write_training();
    write_test();
    readback_checks();
    run_kbest_and_buffer();
    $display("All checks passed.");
    #50;
    $finish;
  end

endmodule
