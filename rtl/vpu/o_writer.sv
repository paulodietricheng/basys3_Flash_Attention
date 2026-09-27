`timescale 1ns/1ps

import fa_pkg::*;

/*
 * ============================================================================
 *  Module: o_writer
 * ============================================================================
 *
 *  Description:
 *      Writes the completed VPU output tile into the O SRAM buffer.
 *
 *      The module captures the full VPU output when vpu_done is asserted, then
 *      packs the output operands into SRAM words and writes them across all
 *      available memory ports.
 *
 *      Operation:
 *
 *          1. Capture the completed output tile from the VPU.
 *          2. Iterate across the D_MODEL dimension in groups of
 *             NUM_PORTS * WPA operands.
 *          3. Pack WPA operands into each SRAM write word.
 *          4. Write NUM_PORTS words in parallel every cycle.
 *          5. Advance through all rows in the output tile.
 *          6. Pulse o_write_done after the complete tile has been written.
 *
 * Author: Paulo Dietrich, assisted by an AI agent
 * ============================================================================
 */

module o_writer (
    input logic clk, rst_n,

    // vpu
    input  operand_t o_in [SA_ROWS][D_MODEL],
    input  logic     vpu_done,

    // o memory
    output logic [BUF_ADDR_W-1:0] wr_addr [NUM_PORTS],
    output logic                  we      [NUM_PORTS],
    output buf_word_t             embd_out[NUM_PORTS],

    // control
    output logic o_write_done
);

    localparam int D_WIDTH        = $clog2(D_MODEL);
    localparam int V_WIDTH        = $clog2(BATCH_SIZE);
    localparam int DIMS_PER_WRITE = NUM_PORTS * WPA;

    typedef enum logic [1:0] {
        o_IDLE,
        o_WRITE,
        o_DONE
    } state_t;

    state_t curr_state;

    // Write position.
    logic [D_WIDTH-1:0] d_idx;
    logic [V_WIDTH-1:0] v_idx;
    logic [BUF_ADDR_W-1:0] word_addr;

    // Registered VPU output tile.
    operand_t o_reg [SA_ROWS][D_MODEL];

    // Capture the completed output tile before beginning the SRAM write.
    always_ff @(posedge clk) begin
        if (rst_n && (curr_state == o_IDLE) && vpu_done) begin
            for (int r = 0; r < SA_ROWS; r++) begin
                for (int c = 0; c < D_MODEL; c++)
                    o_reg[r][c] <= o_in[r][c];
            end
        end
    end

    // Control the output write traversal.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            curr_state <= o_IDLE;
            d_idx      <= '0;
            v_idx      <= '0;
            word_addr  <= '0;
        end else begin
            case (curr_state)

                // Wait for the VPU to complete a tile.
                o_IDLE: begin
                    d_idx     <= '0;
                    v_idx     <= '0;
                    word_addr <= '0;

                    if (vpu_done)
                        curr_state <= o_WRITE;
                end

                // Write NUM_PORTS SRAM words per cycle.
                o_WRITE: begin
                    if (d_idx == D_WIDTH'(D_MODEL - DIMS_PER_WRITE)) begin
                        d_idx <= '0;

                        if (v_idx == V_WIDTH'(BATCH_SIZE - 1))
                            curr_state <= o_DONE;
                        else begin
                            v_idx     <= v_idx + 1'b1;
                            word_addr <= word_addr + BUF_ADDR_W'(NUM_PORTS);
                        end
                    end else begin
                        d_idx     <= d_idx + D_WIDTH'(DIMS_PER_WRITE);
                        word_addr <= word_addr + BUF_ADDR_W'(NUM_PORTS);
                    end
                end

                // Pulse completion for one cycle.
                o_DONE:
                    curr_state <= o_IDLE;

                default: begin
                    curr_state <= o_IDLE;
                    d_idx      <= '0;
                    v_idx      <= '0;
                    word_addr  <= '0;
                end

            endcase
        end
    end

    assign o_write_done = rst_n && (curr_state == o_DONE);

    // Pack operands and drive all output SRAM ports in parallel.
    generate
        for (genvar p = 0; p < NUM_PORTS; p++) begin : GEN_PORTS
            assign we[p]      = rst_n && (curr_state == o_WRITE);
            assign wr_addr[p] = we[p] ? (word_addr + BUF_ADDR_W'(p)) : '0;

            for (genvar b = 0; b < WPA; b++) begin : GEN_OPERANDS
                localparam int DIM_OFFSET = p * WPA + b;
                localparam int SLICE_MSB  = BUF_PORT_W - 1 - b * OPERAND_W;

                assign embd_out[p][SLICE_MSB -: OPERAND_W] = we[p] ? o_reg[v_idx][int'(d_idx) + DIM_OFFSET] : '0;
            end
        end
    endgenerate

endmodule