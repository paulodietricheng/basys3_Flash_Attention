`timescale 1ns / 1ps

import fa_pkg::*;

module vpu_v_fetch (
    input  logic clk,
    input logic rst_n,

    // V fetch index
    //
    // vf_idx[3:1] = row index
    // vf_idx[0]   = dimension iteration
    //
    // 0:  V[0][0:7]
    // 1:  V[0][8:15]
    // 2:  V[1][0:7]
    // 3:  V[1][8:15]
    // ...
    // 14: V[7][0:7]
    // 15: V[7][8:15]
    input logic [V_IDX_W-1:0] vf_idx,

    input  logic vf_start,
    output logic vf_busy,
    output logic vf_done,

    // Data returned from SRAM.
    //
    // Each SRAM port provides WPA operands, so NUM_PORTS*WPA
    // operands arrive per cycle.
    input operand_t v_mbd [NUM_PORTS*WPA],

    // Complete V tile
    output operand_t v_tile [SA_ROWS][D_MODEL]
);

    // ============================================================
    // Parameters
    // ============================================================

    localparam int NUM_OPERANDS = NUM_PORTS * WPA;

    // Number of dimensions loaded in each iteration.
    localparam int DIMS_PER_ITER = NUM_OPERANDS;

    // Number of iterations required to load one row.
    localparam int NUM_ITERS =
        (D_MODEL + DIMS_PER_ITER - 1) / DIMS_PER_ITER;

    // ============================================================
    // Index decoding
    // ============================================================

    // vf_idx = {row_idx, iter_idx}
    //
    // For the intended 8x16 tile:
    //
    // vf_idx[3:1] = row
    // vf_idx[0]   = iteration
    //
    logic [V_IDX_W-1:0] row_idx;
    logic               iter_idx;

    assign row_idx  = vf_idx[V_IDX_W-1:1];
    assign iter_idx = vf_idx[0];

    // Starting dimension for this fetch.
    //
    // iteration 0 -> 0
    // iteration 1 -> NUM_OPERANDS
    //
    localparam int OFFSET_W =
        (D_MODEL <= 1) ? 1 : $clog2(D_MODEL);

    logic [OFFSET_W-1:0] dim_offset;

    assign dim_offset =
        iter_idx ? DIMS_PER_ITER : 0;


    // ============================================================
    // FSM
    // ============================================================

    typedef enum logic [1:0] {
        VF_IDLE,
        VF_LOAD,
        VF_DONE
    } vf_state_t;

    vf_state_t state;


    // ============================================================
    // Main control
    // ============================================================

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state   <= VF_IDLE;
            vf_busy <= 1'b0;
            vf_done <= 1'b0;

            // Clear V tile
            for (int r = 0; r < SA_ROWS; r++) begin
                for (int d = 0; d < D_MODEL; d++) begin
                    v_tile[r][d] <= '0;
                end
            end

        end else begin

            // ----------------------------------------------------
            // Defaults
            // ----------------------------------------------------

            vf_done <= 1'b0;


            case (state)

                // =================================================
                // IDLE
                // =================================================

                VF_IDLE: begin

                    vf_busy <= 1'b0;

                    if (vf_start) begin

                        vf_busy <= 1'b1;
                        state   <= VF_LOAD;

                    end

                end


                // =================================================
                // LOAD
                // =================================================
                //
                // One fetch occurs every cycle.
                //
                // vf_idx identifies where v_mbd belongs.
                //
                // Example:
                //
                // vf_idx = 4'b0101
                //
                // row_idx  = 3'b010 = row 2
                // iter_idx = 1      = dimensions 8:15
                //
                // Therefore:
                //
                // v_mbd[0] -> V[2][8]
                // v_mbd[1] -> V[2][9]
                // ...
                //
                // =================================================

                VF_LOAD: begin

                    vf_busy <= 1'b1;

                    // ------------------------------------------------
                    // Store incoming operands into V tile.
                    //
                    // NUM_OPERANDS is normally 8:
                    //
                    // v_mbd[0] -> first dimension
                    // v_mbd[1] -> second dimension
                    // ...
                    // v_mbd[7] -> eighth dimension
                    // ------------------------------------------------

                    for (int i = 0; i < NUM_OPERANDS; i++) begin

                        if ((dim_offset + i) < D_MODEL) begin

                            v_tile[row_idx][dim_offset + i]
                                <= v_mbd[i];

                        end

                    end


                    // ------------------------------------------------
                    // Last fetch?
                    //
                    // For the intended 8x16 case:
                    //
                    // vf_idx = 15
                    //
                    // means:
                    //
                    // row  = 7
                    // iter = 1
                    //
                    // which is V[7][8:15].
                    // ------------------------------------------------

                    if (vf_idx == V_IDX_W'(SA_ROWS * NUM_ITERS - 1)) begin

                        state <= VF_DONE;

                    end

                end


                // =================================================
                // DONE
                // =================================================

                VF_DONE: begin

                    vf_busy <= 1'b0;
                    vf_done <= 1'b1;

                    state <= VF_IDLE;

                end


                // =================================================
                // Default
                // =================================================

                default: begin

                    state   <= VF_IDLE;
                    vf_busy <= 1'b0;
                    vf_done <= 1'b0;

                end

            endcase

        end

    end

endmodule