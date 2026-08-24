`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.07.2026 19:19:14
// Design Name: 
// Module Name: fa_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

import fa_pkg::*;

module fa_top (
    input clk, rst_n
);

    // TODO (Q4): no central FSM instantiated yet - these are stubs
    // until fa_control (or equivalent) lands here.
    logic       mxu_start;
    logic       mxu_done;
    mxu_cmd_t   mxu_cmd;
    logic       vpu_start;
    logic       vpu_done;

    // -----------------
    // MXU
    // -----------------
    logic   mxu_using_mem;
    k_dim_t a_k_rd_idx;
    k_dim_t b_k_rd_idx;

    sram_word_t in_a [NUM_PORTS];
    sram_word_t in_b [NUM_PORTS];

    accumulator_t c [0:SA_ROWS-1][0:SA_COLS-1];

    mxu U_MXU (
        .clk          (clk),
        .rst_n        (rst_n),
        .mxu_start    (mxu_start),
        .mxu_done     (mxu_done),
        .mxu_cmd      (mxu_cmd),
        .mxu_using_mem(mxu_using_mem),
        .in_a         (in_a),
        .in_b         (in_b),
        .a_k_rd_idx   (a_k_rd_idx),
        .b_k_rd_idx   (b_k_rd_idx),
        .c            (c)
    );

    // -----------------
    // VPU
    // -----------------
    // TODO (Q1 again): same sram_word_t -> operand_t gap for v_mbd.
    sram_word_t v_mbd_word [NUM_PORTS];

    // NOTE: assumes bug 10 fixed (vf_idx_out sized [V_IDX_W-1:0]).
    logic [V_IDX_W-1:0] vf_idx_out;
    operand_t O_N [0:SA_ROWS][0:D_MODEL];

    vpu U_VPU (
        .clk       (clk),
        .rst_n     (rst_n),
        .scores    (c),
        .vpu_start (vpu_start),
        .v_mbd     (v_mbd),
        .vf_idx_out(vf_idx_out),
        .O_N       (O_N),
        .vpu_done  (vpu_done)
    );

    // -----------------
    // SRAM
    // -----------------
    sram_word_t din       [NUM_BUF][NUM_PORTS]; // TODO (Q3): no DMA instantiated -> undriven
    logic       read_bank [NUM_BUF];
    logic [SRAM_ADDR_W-1:0] wr_addr [NUM_BUF][NUM_PORTS]; // TODO (Q3): undriven, no DMA
    logic [SRAM_ADDR_W-1:0] rd_addr [NUM_BUF][NUM_PORTS];
    sram_word_t dout      [NUM_BUF][NUM_PORTS];

    logic mxu_using_mem; 
    logic vpu_using_mem_buf [NUM_BUF]; // TODO (Q2): vpu has no using_mem output at all yet
    logic sram_busy         [NUM_BUF];

    sram U_SRAM (
        .clk          (clk),
        .din          (din),
        .read_bank    (read_bank),
        .wr_addr      (wr_addr),
        .rd_addr      (rd_addr),
        .dout         (dout),
        .mxu_using_mem(mxu_using_mem_buf),
        .vpu_using_mem(vpu_using_mem_buf),
        .busy         (sram_busy)
    );

    // -----------------
    // sram_ctrl
    // -----------------
    sram_ctrl U_SCTRL (
        .clk       (clk),
        .rst_n     (rst_n),
        .a_k_rd_idx(a_k_rd_idx),
        .b_k_rd_idx(b_k_rd_idx),
        .vf_idx    (vf_idx_out),
        .rd_addr   (rd_addr)
    );

endmodule