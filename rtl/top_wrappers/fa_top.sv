`timescale 1ns/1ps

import fa_pkg::*;

/*
 * ============================================================================
 *  Module: fa_top
 * ============================================================================
 *
 *  Description:
 *      Top-level integration module for the Flash Attention accelerator.
 *
 *      The module connects the attention controller, MXU, VPU, SRAM controller,
 *      output writer, and the internal Q/K/V/O memories.
 *
 *      Q, K, and V are loaded through the host interface while the accelerator
 *      is idle. The O buffer can be read through either the host interface or
 *      the dedicated output read interface.
 *
 *      During execution:
 *
 *          1. attention_ctrl schedules Q/K/V tiles and starts the MXU.
 *          2. sram_ctrl generates the Q/K/V memory read addresses.
 *          3. mxu computes the Q*K^T score tile.
 *          4. vpu processes the scores and V data to generate O.
 *          5. o_writer stores the final output tile into the O buffer.
 *
 *  All modules below this were mainly written by Paulo Dietrich, with minimal interaction 
 *  with AI. Every module where AI playied a role has a disclaimer in author.  
 *
 * Author: Paulo Dietrich, assisted by an AI agent
 * ============================================================================
 */

module fa_top #(
    parameter bit QK_DENSE_LAYOUT = 1'b0,
    parameter Q_INIT_FILE = "",
    parameter K_INIT_FILE = "",
    parameter V_INIT_FILE = ""
) (
    input logic clk, rst_n,

    // control
    input  logic                         start,
    input  logic [MAX_TILE_SQ_LEN_W-1:0] tile_sq_len,
    output logic                         busy,
    output logic                         done,
    output logic                         config_error,

    // host
    input  logic                  host_req,
    input  logic                  host_we,
    input  logic [1:0]            host_bank,
    input  logic [BUF_ADDR_W-1:0] host_addr,
    input  buf_word_t             host_wdata,
    output logic                  host_ready,
    output logic                  host_rsp_valid,
    output buf_word_t             host_rdata,

    // output read
    input  logic                  o_rd_en,
    input  logic [BUF_ADDR_W-1:0] o_rd_addr [NUM_PORTS],
    output buf_word_t             o_rd_data [NUM_PORTS],
    output logic                  o_rd_valid,

    // output write
    output logic o_write_done
);

    // sram read
    logic rd_en [NUM_BUF];
    logic [BUF_ADDR_W-1:0] rd_addr [NUM_BUF][NUM_PORTS];
    logic [BUF_ADDR_W-1:0] compute_rd_addr [NUM_BUF][NUM_PORTS];
    buf_word_t rd_data [NUM_BUF][NUM_PORTS];

    // output write
    logic [BUF_ADDR_W-1:0] o_wr_addr [NUM_PORTS];
    logic o_we [NUM_PORTS];
    buf_word_t embd_out [NUM_PORTS];

    // sram write
    buf_word_t mem_din [NUM_BUF][NUM_PORTS];
    logic mem_we [NUM_BUF][NUM_PORTS];
    logic [BUF_ADDR_W-1:0] mem_wr_addr [NUM_BUF][NUM_PORTS];

    // control
    logic ctrl_busy, ctrl_done, accept_start, valid_length;
    logic [MAX_TILE_SQ_LEN_W-1:0] seq_len_reg;

    // host
    logic host_accept;
    logic [1:0] host_bank_d;

    // mxu / vpu
    mxu_cmd_t mxu_cmd;
    logic mxu_start, mxu_done, vpu_done, first_kv, last_kv, retire_op;
    logic mxu_using_mem [2];
    logic vpu_using_mem, vpu_rd_valid;

    // sram address generation
    k_dim_t a_k_rd_idx, b_k_rd_idx;
    logic [V_IDX_W-1:0]    vf_idx;
    logic [BUF_ADDR_W-1:0] qk_stride_words;
    logic [BUF_ADDR_W-1:0] local_o_addr [NUM_PORTS];

    // datapath
    operand_t     in_a[SA_ROWS], in_b[SA_COLS], v_mbd[NUM_PORTS*WPA];
    accumulator_t scores[SA_ROWS][SA_COLS];
    operand_t     O_N[SA_ROWS][D_MODEL];

    // Validate the requested sequence length.
    assign valid_length = (tile_sq_len != 0) &&
                          (tile_sq_len <= MAX_TILE_SQ_LEN_W'(MAX_TOKENS)) &&
                          ((tile_sq_len % BATCH_SIZE) == 0);

    // Accept a new job only when the accelerator is idle.
    assign accept_start = rst_n && start && !ctrl_busy && !ctrl_done && valid_length;

    // Host memory accesses are only allowed while the accelerator is idle.
    assign host_ready = rst_n && !ctrl_busy && !ctrl_done && !accept_start;
    assign host_accept = host_req && host_ready;

    // Delay the selected host bank to match the SRAM read latency.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            host_rsp_valid <= 0;
            host_bank_d    <= '0;
        end else begin
            host_rsp_valid <= host_accept;
            if(host_accept)
                host_bank_d <= host_bank;
        end
    end

    // Host reads use port 0 of the selected memory bank.
    assign host_rdata = rd_data[host_bank_d][0];

    // Status outputs.
    assign config_error = rst_n && start && !ctrl_busy && !ctrl_done && !valid_length;
    assign busy = rst_n && ctrl_busy;
    assign done = rst_n && ctrl_done;

    // Track the first and last K/V tiles of the current Q tile.
    assign first_kv = mxu_cmd.b_n_offset == '0;
    assign last_kv = MAX_TILE_SQ_LEN_W'(mxu_cmd.b_n_offset) == seq_len_reg - MAX_TILE_SQ_LEN_W'(BATCH_SIZE);

    // Final tile retires after the output has been written to memory.
    assign retire_op = last_kv ? o_write_done : vpu_done;

    // Select between dense and fixed Q/K memory layout.
    assign qk_stride_words = QK_DENSE_LAYOUT ? BUF_ADDR_W'(seq_len_reg/WPA) : BUF_ADDR_W'(ADDR_PER_DIM);

    // Store the active sequence length.
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            seq_len_reg <= '0;
        else if (accept_start)
            seq_len_reg <= tile_sq_len;

    // Controls the sequence tiling and compute schedule.
    attention_ctrl U_CTRL (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (accept_start),
        .tile_sq_len(tile_sq_len),
        .busy       (ctrl_busy),
        .done       (ctrl_done),
        .mxu_start  (mxu_start),
        .mxu_cmd    (mxu_cmd),
        .vpu_done   (retire_op)
    );

    // Computes the Q*K^T score tile.
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
        .a_m_rd_offset(),
        .b_n_rd_offset(),
        .c            (scores)
    );

    // Processes the score tile and V data.
    vpu U_VPU (
        .clk          (clk),
        .rst_n        (rst_n),
        .scores       (scores),
        .vpu_start    (rst_n && mxu_done),
        .first_kv     (first_kv),
        .v_mbd        (v_mbd),
        .vf_idx_out   (vf_idx),
        .vpu_using_mem(vpu_using_mem),
        .vpu_rd_valid (vpu_rd_valid),
        .O_N          (O_N),
        .vpu_done     (vpu_done)
    );

    // Generates Q/K/V SRAM read addresses for the compute datapath.
    sram_ctrl U_SCTRL (
        .a_k_rd_idx     (a_k_rd_idx),
        .b_k_rd_idx     (b_k_rd_idx),
        .a_m_rd_offset  (mxu_cmd.a_m_offset),
        .b_n_rd_offset  (mxu_cmd.b_n_offset),
        .qk_stride_words(qk_stride_words),
        .vf_idx         (vf_idx),
        .rd_addr        (compute_rd_addr)
    );

    // Writes the completed output tile into the O buffer.
    o_writer U_WRITER (
        .clk         (clk),
        .rst_n       (rst_n),
        .o_in        (O_N),
        .vpu_done    (vpu_done && last_kv),
        .wr_addr     (local_o_addr),
        .we          (o_we),
        .embd_out    (embd_out),
        .o_write_done(o_write_done)
    );

    // Internal Q/K/V/O memories.
    sram #(
        .Q_INIT_FILE(Q_INIT_FILE),
        .K_INIT_FILE(K_INIT_FILE),
        .V_INIT_FILE(V_INIT_FILE)
    ) U_SRAM (
        .clk    (clk),
        .rst_n  (rst_n),
        .din    (mem_din),
        .we     (mem_we),
        .wr_addr(mem_wr_addr),
        .rd_en  (rd_en),
        .rd_addr(rd_addr),
        .dout   (rd_data)
    );

    // Q memory: MXU or host read.
    assign rd_en[0] = (rst_n && mxu_using_mem[0]) || (host_accept && !host_we && host_bank == 0);

    // K memory: MXU or host read.
    assign rd_en[1] = (rst_n && mxu_using_mem[1]) || (host_accept && !host_we && host_bank == 1);

    // V memory: VPU or host read.
    assign rd_en[2] = vpu_rd_valid || (host_accept && !host_we && host_bank == 2);

    // O memory: direct output read or host read.
    assign rd_en[3] = (rst_n && o_rd_en && !ctrl_busy && !accept_start && !host_req) ||
                     (host_accept && !host_we && host_bank==3);

    // Direct O reads become valid one cycle after the request.
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            o_rd_valid <= 1'b0;
        else
            o_rd_valid <= rd_en[3] && !host_accept;

    // Route host and compute accesses into the four SRAM banks.
    for (genvar b = 0; b < NUM_BUF; b++) begin : GEN_MEM_BUS
        for (genvar p = 0; p < NUM_PORTS; p++) begin : GEN_PORT
            if (b == 3) begin : g_output
                assign mem_din[b][p]     = (host_accept && host_bank==2'(b) && p==0) ?
                                            host_wdata : embd_out[p];
                assign mem_we [b][p]     = o_we[p] || (host_accept && host_we && host_bank ==
                                           2'(b) && p==0);
                assign mem_wr_addr[b][p] = (host_accept && host_bank==2'(b) && p==0) ?
                                            host_addr : o_wr_addr[p];
                
                assign rd_addr[b][p]     = (host_accept && host_bank==2'(b)) ? host_addr : o_rd_addr[p];
            end else begin : g_input
                assign mem_din[b][p] = host_wdata;
                assign mem_we[b][p] = host_accept && host_we && host_bank==2'(b) && p==0;
                assign mem_wr_addr[b][p] = host_addr;
                assign rd_addr[b][p] = (host_accept && host_bank==2'(b)) ? host_addr : compute_rd_addr[b][p];
            end
        end
    end

    // Connect O-buffer reads and generate the final output write address.
    for (genvar p = 0; p < NUM_PORTS; p++) begin : GEN_WR_ADDR
        assign o_rd_data[p] = rd_data[3][p];
        assign o_wr_addr[p] = o_we[p] ? local_o_addr[p] + BUF_ADDR_W'(int'(mxu_cmd.a_m_offset) * 
                                                          (D_MODEL / WPA)) : '0;
    end

    // Extract packed Q operands from SRAM words.
    for (genvar r = 0; r < SA_ROWS; r++) begin : GEN_Q
        assign in_a[r] = operand_t'(rd_data[0][r / WPA][BUF_PORT_W - 1 -
                                   (r % WPA) * OPERAND_W -: OPERAND_W]);
    end

    // Extract packed K operands from SRAM words.
    for (genvar r = 0; r < SA_COLS; r++) begin : GEN_K
        assign in_b[r] = operand_t'(rd_data[1][r / WPA][BUF_PORT_W - 1 - 
                                   (r % WPA) * OPERAND_W -: OPERAND_W]);
    end

    // Extract packed V operands from SRAM words.
    for (genvar r = 0; r < NUM_PORTS * WPA; r++) begin : GEN_V
        assign v_mbd[r] = operand_t'(rd_data[2][r / WPA][BUF_PORT_W - 1 - 
                                    (r % WPA) * OPERAND_W -: OPERAND_W]);
    end

    // Verify that the package parameters describe a supported compute geometry.
    // synthesis translate_off
    initial begin
        assert (NUM_BUF == 4 && SA_ROWS == BATCH_SIZE && SA_COLS == BATCH_SIZE &&
                SA_ROWS == NUM_PORTS*WPA && SA_COLS == NUM_PORTS*WPA &&
                D_MODEL % (NUM_PORTS*WPA) == 0 && ACC_W == 32)
            else $fatal(1,"Unsupported compute geometry");
    end
    // synthesis translate_on

endmodule