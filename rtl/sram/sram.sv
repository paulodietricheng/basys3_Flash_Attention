`timescale 1ns/1ps

import fa_pkg::*;

/*
 * ============================================================================
 *  Module: sram
 * ============================================================================
 *
 *  Description:
 *      SRAM wrapper for the Q, K, V, and O buffers used by the Flash Attention
 *      accelerator.
 *
 *      Each logical buffer is implemented as one dual-port BRAM. There is no
 *      ping-pong buffering or bank switching inside this module.
 *
 *      For each BRAM port, writes have priority over reads. When no write is
 *      active, the corresponding read address is selected if rd_en is asserted.
 *
 *      The Q, K, and V buffers may optionally be initialized from memory files.
 *      The O buffer is always created without an initialization file.
 *
 * Author: Paulo Dietrich
 * ============================================================================
 */

module sram #(
    parameter Q_INIT_FILE = "",
    parameter K_INIT_FILE = "",
    parameter V_INIT_FILE = ""
) (
    input logic clk, rst_n,

    // write
    input buf_word_t             din     [NUM_BUF][NUM_PORTS],
    input logic                  we      [NUM_BUF][NUM_PORTS],
    input logic [BUF_ADDR_W-1:0] wr_addr [NUM_BUF][NUM_PORTS],

    // read
    input logic                  rd_en   [NUM_BUF],
    input logic [BUF_ADDR_W-1:0] rd_addr [NUM_BUF][NUM_PORTS],
    output buf_word_t            dout    [NUM_BUF][NUM_PORTS]
);

    // Instantiate one dual-port BRAM for each logical buffer.
    for (genvar b = 0; b < NUM_BUF; b++) begin : GEN_BUF
        localparam INIT_FILE = (b==0) ? Q_INIT_FILE :
                               (b==1) ? K_INIT_FILE :
                               (b==2) ? V_INIT_FILE : "";

        logic [BUF_ADDR_W-1:0] port_addr [NUM_PORTS];
        logic                  port_we   [NUM_PORTS];

        // Select either the write or read address for each physical BRAM port.
        for (genvar p = 0; p < NUM_PORTS; p++) begin : GEN_PORT
            assign port_we[p]   = rst_n && we[b][p];
            assign port_addr[p] = port_we[p] ? wr_addr[b][p] :
                                  (rst_n && rd_en[b]) ? rd_addr[b][p] : '0;
        end

        bram #(
            .DATA_W   (BUF_PORT_W),
            .ADDR_W   (BUF_ADDR_W),
            .INIT_FILE(INIT_FILE)
        ) U_BRAM (
            .clk   (clk),
            .din_a (din[b][0]),
            .addr_a(port_addr[0]),
            .we_a  (port_we[0]),
            .dout_a(dout[b][0]),
            .din_b (din[b][1]),
            .addr_b(port_addr[1]),
            .we_b  (port_we[1]),
            .dout_b(dout[b][1])
        );
    end

    // Verify that the wrapper matches the expected memory architecture.
    // synthesis translate_off
    initial assert (NUM_BUF == 4 && NUM_PORTS == 2 && BUF_DEPTH == (1<<BUF_ADDR_W))
        else $fatal(1,"SRAM wrapper requires four power-of-two-depth dual-port buffers");
    // synthesis translate_on

endmodule