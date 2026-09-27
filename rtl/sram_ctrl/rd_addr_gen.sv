`timescale 1ns/1ps

import fa_pkg::*;

/*
 * ============================================================================
 *  Module: rd_addr_gen
 * ============================================================================
 *
 *  Description:
 *      Generates SRAM read addresses for the Q, K, and V memory banks.
 *
 *      The module converts the current MXU and VPU indices into packed memory
 *      addresses according to the configured Q/K stride and the number of
 *      operands stored in each SRAM word.
 *
 *      Address generation:
 *
 *          Q buffer:
 *              Uses the current A-side K index and Q-row offset.
 *
 *          K buffer:
 *              Uses the current B-side K index and K-column offset.
 *
 *          V buffer:
 *              Uses the current K/V batch offset and V fetch index.
 *
 *      The O-buffer read addresses are not generated here and remain zero.
 *
 * Author: Paulo Dietrich, assisted by an AI Agent. 
 * ============================================================================
 */

module rd_addr_gen (
    // mxu
    input k_dim_t a_k_rd_idx,
    input k_dim_t b_k_rd_idx,
    input m_dim_t a_m_rd_offset,
    input n_dim_t b_n_rd_offset,

    // memory layout
    input logic [BUF_ADDR_W-1:0] qk_stride_words,

    // vpu
    input logic [V_IDX_W-1:0] vf_idx,

    // sram
    output logic [BUF_ADDR_W-1:0] rd_addr [NUM_BUF][NUM_PORTS]
);

    // Number of packed SRAM words required for one D_MODEL row.
    localparam int WORDS_PER_ROW = D_MODEL/WPA;

    always_comb begin
        // Default all SRAM read addresses to zero.
        for (int b = 0; b < NUM_BUF; b++)
            for (int p = 0; p < NUM_PORTS; p++)
                rd_addr[b][p] = '0;

        // Generate Q, K, and V read addresses for each SRAM port.
        for (int p = 0; p < NUM_PORTS; p++) begin
            rd_addr[0][p] = BUF_ADDR_W'(int'(a_k_rd_idx)*int'(qk_stride_words) + int'(a_m_rd_offset)/WPA + p);
            rd_addr[1][p] = BUF_ADDR_W'(int'(b_k_rd_idx)*int'(qk_stride_words) + int'(b_n_rd_offset)/WPA + p);
            rd_addr[2][p] = BUF_ADDR_W'(int'(b_n_rd_offset)*WORDS_PER_ROW + int'(vf_idx)*NUM_PORTS + p);
        end
    end

endmodule