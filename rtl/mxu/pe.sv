`timescale 1ns/1ps

import fa_pkg::*;

/*
 * ============================================================================
 *  Module: pe
 * ============================================================================
 *
 *  Description:
 *      Processing element used inside the MXU systolic array.
 *
 *      Each PE receives one A operand from the left and one B operand from the
 *      top. When array_en is asserted, the operands are registered and forwarded
 *      to the neighboring processing elements.
 *
 *      The PE also performs a multiply-accumulate operation:
 *
 *          acc = acc + A * B
 *
 *      Operation:
 *
 *          1. Register incoming A and B operands when the array is enabled.
 *          2. Forward the registered operands to the next PE.
 *          3. Multiply the registered operands and accumulate the result.
 *          4. Clear both operand registers and the accumulator when clr_acc_n
 *             is deasserted.
 *
 *      The accumulator is explicitly mapped to DSP resources when supported by
 *      the synthesis tool.
 *
 * Author: Paulo Dietrich
 * ============================================================================
 */

module pe (
    input logic clk, rst_n,

    // control
    input logic clr_acc_n,
    input logic array_en,

    // operands
    input operand_t in_a,
    input operand_t in_b,

    // systolic outputs
    output operand_t out_a,
    output operand_t out_b,

    // accumulator
    output accumulator_t c
);

    // Registered operands forwarded through the systolic array.
    operand_t areg, breg;

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            areg <= '0;
            breg <= '0;
        end else if(!clr_acc_n) begin
            areg <= '0;
            breg <= '0;
        end else if(array_en) begin
            areg <= in_a;
            breg <= in_b;
        end
    end

    assign out_a = areg;
    assign out_b = breg;

    // Accumulator mapped to DSP hardware.
    (* use_dsp = "yes", multstyle = "dsp" *) accumulator_t acc_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            acc_reg <= '0;
        // Clear is independent of array_en.
        else if(!clr_acc_n)
            acc_reg <= '0;
        else if(array_en)
            acc_reg <= acc_reg + (areg*breg);
    end

    assign c = acc_reg;

endmodule