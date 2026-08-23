`timescale 1ns / 1ps

import fa_pkg::*;

module vpu_v_fetch (
    input  logic clk,
    input  logic rst_n,

    // ------------------------------------------------------------
    // V fetch index
    //
    // vf_idx[3:1] = row
    // vf_idx[0]   = iteration
    //
    // For an 8x16 V tile:
    //
    // 0  -> V[0][0:7]
    // 1  -> V[0][8:15]
    // 2  -> V[1][0:7]
    // 3  -> V[1][8:15]
    // ...
    // 14 -> V[7][0:7]
    // 15 -> V[7][8:15]
    //
    // vf_idx is sent to the address generator, which drives the
    // SRAM. The SRAM has one-cycle latency.
    // ------------------------------------------------------------

    input logic [V_IDX_W-1:0] vf_idx,

    input  logic vf_start,
    output logic vf_busy,
    output logic vf_done,

    // ------------------------------------------------------------
    // SRAM data
    //
    // NUM_PORTS SRAM ports, WPA operands per port.
    //
    // Total operands received per cycle:
    //
    //     NUM_PORTS * WPA
    //
    // Example:
    //     NUM_PORTS = 2
    //     WPA       = 4
    //     => 8 operands/cycle
    // ------------------------------------------------------------

    input operand_t v_mbd [NUM_PORTS*WPA],

    // ------------------------------------------------------------
    // Complete V tile
    // ------------------------------------------------------------

    output operand_t v_tile [SA_ROWS][D_MODEL]
);
    localparam int NUM_OPERANDS = NUM_PORTS * WPA;

    // Number of dimensions loaded by one SRAM fetch.
    localparam int DIMS_PER_ITER = NUM_OPERANDS;

    // Number of fetches required per row.
    localparam int NUM_ITERS = (D_MODEL + DIMS_PER_ITER - 1) / DIMS_PER_ITER;

    // Total number of fetches for the entire tile.
    localparam int TOTAL_FETCHES = SA_ROWS * NUM_ITERS;

    logic [V_IDX_W-1:0] vf_idx_d;

    logic vf_idx_valid_d;

    logic [V_IDX_W-2:0] row_idx_d;
    logic               iter_idx_d;

    assign row_idx_d  = vf_idx_d[V_IDX_W-1:1];
    assign iter_idx_d = vf_idx_d[0];

    localparam int OFFSET_W = (D_MODEL <= 1) ? 1 : $clog2(D_MODEL);

    logic [OFFSET_W-1:0] dim_offset_d;

    assign dim_offset_d = iter_idx_d ? DIMS_PER_ITER : 0;

    typedef enum logic [1:0] {
        VF_IDLE,
        VF_LOAD
    } vf_state_t;

    vf_state_t state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= VF_IDLE;

            vf_busy        <= 1'b0;
            vf_done        <= 1'b0;

            vf_idx_d       <= '0;
            vf_idx_valid_d <= 1'b0;

            // Clear V tile
            for (int r = 0; r < SA_ROWS; r++) begin
                for (int d = 0; d < D_MODEL; d++) begin
                    v_tile[r][d] <= '0;
                end
            end
        end else begin
            vf_done <= 1'b0;

            case (state)

                VF_IDLE: begin
                    vf_busy        <= 1'b0;
                    vf_idx_valid_d <= 1'b0;

                    if (vf_start) begin
                        vf_busy <= 1'b1;

                        vf_idx_d       <= vf_idx;
                        vf_idx_valid_d <= 1'b1;

                        state <= VF_LOAD;
                    end
                end

                VF_LOAD: begin
                    vf_busy <= 1'b1;
                    if (vf_idx_valid_d) begin
                        for (int i = 0; i < NUM_OPERANDS; i++) begin
                            if ((dim_offset_d + i) < D_MODEL) begin
                                v_tile[row_idx_d][dim_offset_d + i] <= v_mbd[i];
                            end
                        end
                        if (vf_idx_d == V_IDX_W'(TOTAL_FETCHES - 1)) begin
                            vf_busy        <= 1'b0;
                            vf_done        <= 1'b1;
                            vf_idx_valid_d <= 1'b0;

                            state <= VF_IDLE;
                        end
                    end
                if (vf_idx_valid_d && (vf_idx_d != V_IDX_W'(TOTAL_FETCHES - 1))) begin
                        vf_idx_d       <= vf_idx;
                        vf_idx_valid_d <= 1'b1;
                    end
                end

                // =================================================
                // Default
                // =================================================
                default: begin
                    state          <= VF_IDLE;
                    vf_busy        <= 1'b0;
                    vf_done        <= 1'b0;
                    vf_idx_d       <= '0;
                    vf_idx_valid_d <= 1'b0;
                end
            endcase
        end
    end
endmodule