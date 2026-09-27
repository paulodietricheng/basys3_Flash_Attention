`timescale 1ns/1ps

import fa_pkg::*;

/*
 * ============================================================================
 *  Module: sram_ctrl
 * ============================================================================
 *
 *  Description:
 *      SRAM address-generation wrapper for the Flash Attention datapath.
 *
 *      This module receives the current MXU and VPU memory indices and forwards
 *      them to rd_addr_gen, which produces the read addresses for the internal
 *      Q, K, V, and O memory banks.
 *
 *      The module performs address generation only. It does not manage double
 *      buffering, bank arbitration, DMA transfers, or memory ownership.
 *
 * Author: Paulo Dietrich
 * ============================================================================
 */

module sram_ctrl (
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

    // Generate the read addresses for all SRAM banks and ports.
    rd_addr_gen U_RAG (
        .a_k_rd_idx    (a_k_rd_idx),
        .b_k_rd_idx    (b_k_rd_idx),
        .a_m_rd_offset (a_m_rd_offset),
        .b_n_rd_offset (b_n_rd_offset),
        .qk_stride_words(qk_stride_words),
        .vf_idx        (vf_idx),
        .rd_addr       (rd_addr)
    );

endmodule