`timescale 1ns/1ps

/*
 * ============================================================================
 *  Module: bram
 * ============================================================================
 *
 *  Description:
 *      Parameterized synchronous true dual-port block RAM.
 *
 *      Both ports can independently read or write the same memory array.
 *      Reads are synchronous and use read-first behavior, meaning dout returns
 *      the previous contents of the addressed location when a write occurs.
 *
 *      The memory contents and output registers are not reset. This allows the
 *      stored Q/K/V/O data to survive a compute-core reset.
 *
 *      An optional initialization file may be provided through INIT_FILE and
 *      loaded using $readmemh during simulation and supported synthesis flows.
 *
 * Author: Paulo Dietrich
 * ============================================================================
 */

module bram #(
    parameter int DATA_W = 32,
    parameter int ADDR_W = 10,
    parameter INIT_FILE = ""
) (
    input logic clk,

    // port A
    input  logic [DATA_W-1:0] din_a,
    input  logic [ADDR_W-1:0] addr_a,
    input  logic              we_a,
    output logic [DATA_W-1:0] dout_a,

    // port B
    input  logic [DATA_W-1:0] din_b,
    input  logic [ADDR_W-1:0] addr_b,
    input  logic              we_b,
    output logic [DATA_W-1:0] dout_b
);

    // Infer block RAM.
    (* ram_style = "block" *) logic [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

    // Optional memory initialization.
    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    // Port A synchronous read/write.
    always_ff @(posedge clk) begin
        if (we_a)
            mem[addr_a] <= din_a;

        dout_a <= mem[addr_a];
    end

    // Port B synchronous read/write.
    always_ff @(posedge clk) begin
        if (we_b)
            mem[addr_b] <= din_b;

        dout_b <= mem[addr_b];
    end

    // Prevent undefined simultaneous writes to the same address.
    // synthesis translate_off
    always @(posedge clk)
        assert (!(we_a && we_b && addr_a == addr_b))
            else $fatal(1,"BRAM simultaneous writes to the same address");
    // synthesis translate_on

endmodule