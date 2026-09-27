`timescale 1ns/1ps

import fa_pkg::*;

/*
 * ============================================================================
 *  Module: fa_uart_top
 * ============================================================================
 *
 *  Description:
 *      Top-level integration module connecting the UART interface to the
 *      Flash Attention accelerator core.
 *
 *      The module instantiates:
 *
 *          1. uart_rx
 *             Receives serial data from the host PC and converts it into
 *             8-bit data bytes.
 *
 *          2. uart_tx
 *             Converts 8-bit response data into a serial UART stream.
 *
 *          3. uart_command
 *             Decodes UART packets, validates commands, controls accelerator
 *             execution, and performs host-side buffer reads and writes.
 *
 *          4. fa_top
 *             Flash Attention accelerator core.
 *
 *      The UART clock divider is calculated from CLK_HZ and BAUD so the same
 *      module can be used with different system clock frequencies.
 *
 *      Host memory accesses are routed from uart_command directly into fa_top,
 *      allowing the PC to initialize and read accelerator buffers.
 *
 * Author: Paulo Dietrich via an agentic workflow
 * ============================================================================
 */

module fa_uart_top #(
    parameter int CLK_HZ=100_000_000,
    parameter int BAUD=115_200,
    parameter int RX_TIMEOUT_CYCLES=CLK_HZ/10
) (
    input  logic clk, rst_n, 
    
    // UART pins
    input  logic uart_rx_pin,
    output logic uart_tx_pin,
    
    // LED flags
    output logic busy, 
    output logic done_latched, 
    output logic error_latched
);

    // Number of system clock cycles per UART bit.
    localparam int CPB = (CLK_HZ + BAUD / 2) / BAUD;
    
    // UART signals
    logic [7:0] rx_data, tx_data;
    logic rx_valid, rx_error, tx_valid, tx_ready;
    
    // Core control signals
    logic core_rst_n, start, done, config_error;
    logic [MAX_TILE_SQ_LEN_W-1:0] tile_sq_len;
    
    // Host interface used by the PC to access accelerator memory.
    logic host_req, host_we, host_ready, host_rsp_valid;
    logic [1:0] host_bank;
    logic [BUF_ADDR_W-1:0] host_addr;
    buf_word_t host_wdata, host_rdata;

    // Output-memory read addresses are unused in the UART integration.
    logic [BUF_ADDR_W-1:0] unused_o_addr[NUM_PORTS];
    
    for(genvar p=0;p<NUM_PORTS;p++)
         assign unused_o_addr[p]='0;
    
    // UART receiver.
    uart_rx #(.CLKS_PER_BIT(CPB)) U_RX (
        .clk(clk),
        .rst_n(rst_n),
        .rx(uart_rx_pin),
        .data(rx_data),
        .valid(rx_valid),
        .framing_error(rx_error)
    );
    
    // UART transmitter.
    uart_tx #(.CLKS_PER_BIT(CPB)) U_TX (
        .clk(clk),
        .rst_n(rst_n),
        .data(tx_data),
        .valid(tx_valid),
        .ready(tx_ready),
        .tx(uart_tx_pin)
    );
    
    // UART packet decoder and accelerator command controller.
    uart_command #(
        .CLK_HZ(CLK_HZ),
        .RX_TIMEOUT_CYCLES(RX_TIMEOUT_CYCLES)
    ) U_CMD (
        .clk(clk),
        .rst_n(rst_n),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .rx_error(rx_error),
        .tx_data(tx_data),
        .tx_valid(tx_valid),
        .tx_ready(tx_ready),
        .core_rst_n(core_rst_n),
        .start(start),
        .tile_sq_len(tile_sq_len),
        .busy(busy),
        .done(done),
        .config_error(config_error),
        .done_latched(done_latched),
        .error_latched(error_latched),
        .host_req(host_req),
        .host_we(host_we),
        .host_bank(host_bank),
        .host_addr(host_addr),
        .host_wdata(host_wdata),
        .host_ready(host_ready),
        .host_rsp_valid(host_rsp_valid),
        .host_rdata(host_rdata)
    );
    
    // Flash Attention accelerator core.
    fa_top U_CORE (
        .clk(clk),
        .rst_n(core_rst_n),
        .start(start),
        .tile_sq_len(tile_sq_len),
        .busy(busy),
        .done(done),
        .config_error(config_error),
        .host_req(host_req),
        .host_we(host_we),
        .host_bank(host_bank),
        .host_addr(host_addr),
        .host_wdata(host_wdata),
        .host_ready(host_ready),
        .host_rsp_valid(host_rsp_valid),
        .host_rdata(host_rdata),

        // Direct output-memory read interface is unused here.
        .o_rd_en(1'b0),
        .o_rd_addr(unused_o_addr),
        .o_rd_data(),
        .o_rd_valid(),
        .o_write_done()
    );

endmodule