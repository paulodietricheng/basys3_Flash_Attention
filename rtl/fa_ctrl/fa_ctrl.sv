`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09.07.2026 17:39:42
// Design Name: 
// Module Name: fa_ctrl
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

module fa_ctrl (
    input logic clk, rst_n,

    // cpu
    input  logic                  fa_start,
    input  logic [MAX_SQ_L_W-1:0] sq_len,
    output logic                  fa_done,

    // mxu
    output logic mxu_start,
    output mxu_cmd_t mxu_cmd,
    input  logic mxu_done, // move to VPU

    // sram_controller
    output logic Q_tile_done,
    output logic KV_tile_done,

    // dma
    output dma_rq_t dma_rq_0,
    output dma_rq_t dma_rq_1    
);

    // Number of BRAM tiles required for the current sequence.
    logic [MAX_TC_W-1:0] num_tiles;
    
    // Tile indices
    logic [MAX_TC_W-1:0] q_tile_idx;
    logic [MAX_TC_W-1:0] kv_tile_idx;
    
    // Current tile sequence lengths
    logic [MAX_SQ_L_W-1:0] q_tile_sq_len;
    logic [MAX_SQ_L_W-1:0] kv_tile_sq_len;
    
    // Number of MXU subtiles in the current tile
    logic [MAX_STC_W-1:0] q_num_subtiles;
    logic [MAX_STC_W-1:0] kv_num_subtiles;
    
    // Subtile indices
    logic [MAX_STC_W-1:0] q_subtile_idx;
    logic [MAX_STC_W-1:0] kv_subtile_idx;
    
    // Compute the number of tiles for the current sequence.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            num_tiles <= '0;
        else if (fa_start)
            num_tiles <= (sq_len + MAX_TILE_SQ_LEN - 1) / MAX_TILE_SQ_LEN;
    end
    
    // Compute Q tile length and subtile count.
    always_comb begin
        if (q_tile_idx == num_tiles-1)
            q_tile_sq_len = sq_len - q_tile_idx * MAX_TILE_SQ_LEN;
        else
            q_tile_sq_len = MAX_TILE_SQ_LEN;
    
        q_num_subtiles = (q_tile_sq_len + SA_ROWS - 1) / SA_ROWS;
    end
    
    // Compute KV tile length and subtile count.
    always_comb begin
        if (kv_tile_idx == num_tiles-1)
            kv_tile_sq_len = sq_len - kv_tile_idx * MAX_TILE_SQ_LEN;
        else
            kv_tile_sq_len = MAX_TILE_SQ_LEN;
    
        kv_num_subtiles = (kv_tile_sq_len + SA_ROWS - 1) / SA_ROWS;
    end
    
    // End-of-loop flags
    logic last_q_tile;
    logic last_kv_tile;
    
    logic last_q_subtile;
    logic last_kv_subtile;
    
    assign last_q_tile  = (q_tile_idx == num_tiles - 1);
    assign last_kv_tile = (kv_tile_idx == num_tiles - 1);
    
    assign last_q_subtile  = (q_subtile_idx == q_num_subtiles - 1);
    assign last_kv_subtile = (kv_subtile_idx == kv_num_subtiles - 1);
    
//    // States
//    typedef enum logic [2:0] {
//        fa_IDLE,
//        fa_LOAD_Qi,
//        fa_LOAD_Ki,
//        fa_QiKi_LOAD_Vi,
//        fa_ONLINE_SOFTMAX_LOAD_Kip1,
//        fa_OUTPUT_On_Qi,
//        fa_DONE
//    } fa_states_t;

//    fa_states_t curr_state;

//    // pulse signals
//    logic dma_req_sent;
//    logic mxu_req_sent;

//    always_ff @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            curr_state        <= fa_IDLE;

//            fa_done            <= 1'b0;
//            mxu_start          <= 1'b0;
//            softmax_start      <= 1'b0;
//            Atile_advance      <= 1'b0;
//            dma_start_request  <= 1'b0;
//            dmaA_wr_done       <= 1'b0;
//            dmaB_wr_done       <= 1'b0;
//            o_valid            <= 1'b0;

//            q_tile_idx <= '0;
//            k_tile_idx <= '0;
//            v_tile_idx <= '0;

//            dma_req_sent <= 1'b0;
//            mxu_req_sent <= 1'b0;
//        end else begin

//            // defaults: deassert every cycle, states below pulse them high
//            dma_start_request <= 1'b0;
//            mxu_start         <= 1'b0;
//            dmaA_wr_done      <= 1'b0;
//            dmaB_wr_done      <= 1'b0;
//            Atile_advance     <= 1'b0;
//            o_valid           <= 1'b0;

//            case (curr_state)
//                fa_IDLE : begin
//                    fa_done      <= 1'b0;
//                    dma_req_sent <= 1'b0;
//                    mxu_req_sent <= 1'b0;

//                    q_tile_idx <= '0;
//                    k_tile_idx <= '0;
//                    v_tile_idx <= '0;

//                    curr_state <= fa_start ? fa_LOAD_Qi : fa_IDLE;
//                end

//                fa_LOAD_Qi : begin
//                    Atile_advance <= 1'b1;   // held for whole state, see db_control

//                    if (!dma_req_sent) begin
//                        dma_start_request <= 1'b1;
//                        dma_req_sent      <= 1'b1;
                        
//                        // Proper request sending to dma
                        
//                    end else begin
//                        dma_start_request <= 1'b0;
//                    end

//                    dmaA_wr_done <= dma_wr_done;
 
//                    if (dma_wr_done) begin
//                        dma_req_sent <= 1'b0;
//                        q_tile_idx   <= q_tile_idx + 1;
//                        k_tile_idx   <= '0;
//                        v_tile_idx   <= '0;
//                        curr_state   <= fa_LOAD_Ki;
//                    end
//                end

//                fa_LOAD_Ki : begin
//                    if (!dma_req_sent) begin
//                        dma_start_request <= 1'b1;
//                        dma_req_sent      <= 1'b1;
                                             
//                        // Proper request sending to dma
                        
//                    end else begin
//                        dma_start_request <= 1'b0;
//                    end

//                    dmaB_wr_done <= dma_wr_done;

//                    if (dma_wr_done) begin
//                        dma_req_sent <= 1'b0;
//                        k_tile_idx   <= k_tile_idx + 1;
//                        v_tile_idx   <= '0;
//                        curr_state   <= fa_QiKi_LOAD_Vi;
//                    end
//                end

//                fa_QiKi_LOAD_Vi : begin
//                    // QK^T
//                    if (!mxu_req_sent) begin
//                        mxu_start    <= 1'b1;
//                        mxu_req_sent <= 1'b1;
//                    end else begin
//                        mxu_start <= 1'b0;
//                    end

//                    // Load Vi
//                    if (!dma_req_sent) begin
//                        dma_start_request <= 1'b1;
//                        dma_req_sent      <= 1'b1;
                                             
//                        // Proper request sending to dma
                        
//                    end else begin
//                        dma_start_request <= 1'b0;
//                    end

//                    dmaB_wr_done <= dma_wr_done;

//                    if (dma_wr_done) begin
//                        dma_req_sent <= 1'b0;
//                        v_tile_idx   <= v_tile_idx + 1;
//                    end 

//                    if (mxu_done) begin
//                        mxu_req_sent <= 1'b0;
//                        curr_state   <= fa_ONLINE_SOFTMAX_LOAD_Kip1;
//                    end
//                end

//                fa_ONLINE_SOFTMAX_LOAD_Kip1 : begin
//                    // Do some softmax logic
                    
//                    // Load Ki+1
//                    if (!dma_req_sent) begin
//                        dma_start_request <= 1'b1;
//                        dma_req_sent      <= 1'b1;
                                             
//                        // Proper request sending to dma
                        
//                    end else begin
//                        dma_start_request <= 1'b0;
//                    end

//                    dmaB_wr_done <= dma_wr_done;

//                    if (dma_wr_done) begin
//                        dma_req_sent <= 1'b0;
//                        k_tile_idx   <= k_tile_idx + 1;
//                    end

//                    if (softmax_done) begin
//                        curr_state <= last_k_tile ? fa_OUTPUT_On_Qi : fa_QiKi_LOAD_Vi;
//                    end
//                end

//                fa_OUTPUT_On_Qi : begin
//                    o_valid <= 1'b1;
//                    curr_state <= last_q_tile ? fa_DONE : fa_LOAD_Qi;
//                end

//                fa_DONE : begin
//                    fa_done    <= 1'b1;
//                    curr_state <= fa_IDLE;
//                end

//                default : curr_state <= fa_IDLE;
//            endcase
//        end
//    end

endmodule
