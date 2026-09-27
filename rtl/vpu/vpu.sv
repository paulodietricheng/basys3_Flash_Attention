import fa_pkg::*;

/*
 * ============================================================================
 *  Module: vpu
 * ============================================================================
 *
 *  Description:
 *      Top-level vector processing unit for the Flash Attention datapath.
 *
 *      The VPU receives one score tile from the MXU and combines it with the
 *      corresponding V tile to update the running Flash Attention state.
 *
 *      Operation:
 *
 *          1. Capture the current score tile.
 *          2. Fetch the corresponding V tile from memory.
 *          3. Process each score row sequentially through vpu_row.
 *          4. Update the running max, denominator, and output accumulators.
 *          5. Normalize the output row and convert it back to operand format.
 *          6. Pulse vpu_done after all rows in the tile have been processed.
 *
 *      When first_kv is asserted, the running state is cleared because the
 *      current operation is the first K/V tile for a new Q batch.
 *
 * Author: Paulo Dietrich
 * ============================================================================
 */

module vpu (
    input logic clk, rst_n,

    // control
    input  logic vpu_start,
    input  logic first_kv,
    output logic vpu_done,

    // mxu
    input accumulator_t scores [0:SA_ROWS-1][0:SA_COLS-1],

    // v memory
    input  operand_t            v_mbd [WPA*NUM_PORTS],
    output logic [V_IDX_W-1:0]  vf_idx_out,
    output logic                vpu_using_mem,
    output logic                vpu_rd_valid,

    // output
    output operand_t O_N [0:SA_ROWS-1][0:D_MODEL-1]
);

    localparam accumulator_t NEG_INF = 32'h80000000;
    localparam ROW_IDX_W = $clog2(SA_ROWS);

    // running flash attention state
    accumulator_t m_i [SA_ROWS], m_i_minus_1 [SA_ROWS];
    accumulator_t d_i [SA_ROWS], d_i_minus_1 [SA_ROWS];
    accumulator_t o_i [SA_ROWS][0:D_MODEL-1];
    accumulator_t o_i_minus_1 [SA_ROWS][0:D_MODEL-1];
    accumulator_t o_norm [SA_ROWS][D_MODEL];

    // vpu row
    logic vpu_row_start, vpu_row_busy, vpu_row_done;
    accumulator_t x_i [0:SA_COLS-1];
    accumulator_t in_m_i, in_m_i_minus_1;
    accumulator_t in_d_i, in_d_i_minus_1, in_d_inv;
    accumulator_t in_o_i [0:D_MODEL-1], in_o_i_minus_1 [0:D_MODEL-1];
    accumulator_t out_m_i, out_m_i_minus_1;
    accumulator_t out_d_i, out_d_i_minus_1, out_d_inv;
    accumulator_t out_o_i [0:D_MODEL-1], out_o_i_minus_1 [0:D_MODEL-1];
    accumulator_t out_o_norm [0:D_MODEL-1];

    // v fetch
    logic vf_start, vf_busy, vf_done;
    operand_t V_reg [0:SA_COLS-1][0:D_MODEL-1];
    operand_t v_tile [SA_COLS][D_MODEL];

    // control
    logic [ROW_IDX_W-1:0] row_idx;
    accumulator_t x_reg [0:SA_ROWS-1][0:SA_COLS-1];

    typedef enum logic [2:0] {
        v_IDLE,
        v_FETCH_START,
        v_FETCH_WAIT,
        v_ROW_PREP,
        v_ROW_START,
        v_ROW_WAIT,
        v_DONE
    } vpu_state_t;

    vpu_state_t curr_state;

    // Processes one attention row at a time.
    vpu_row U_VROW (
        .clk            (clk),
        .rst_n          (rst_n),
        .vpu_row_start  (vpu_row_start),
        .vpu_row_busy   (vpu_row_busy),
        .vpu_row_done   (vpu_row_done),
        .x_i            (x_i),
        .in_m_i         (in_m_i),
        .in_m_i_minus_1 (in_m_i_minus_1),
        .in_d_i         (in_d_i),
        .in_d_i_minus_1 (in_d_i_minus_1),
        .in_o_i         (in_o_i),
        .in_o_i_minus_1 (in_o_i_minus_1),
        .V              (V_reg),
        .out_m_i        (out_m_i),
        .out_m_i_minus_1(out_m_i_minus_1),
        .out_d_i        (out_d_i),
        .out_d_i_minus_1(out_d_i_minus_1),
        .out_o_i        (out_o_i),
        .out_o_i_minus_1(out_o_i_minus_1),
        .out_o_norm     (out_o_norm)
    );

    // Fetches the V tile corresponding to the current K/V batch.
    vpu_v_fetch U_VF (
        .clk        (clk),
        .rst_n      (rst_n),
        .vf_idx_out (vf_idx_out),
        .vf_rd_valid(vpu_rd_valid),
        .vf_start   (vf_start),
        .vf_busy    (vf_busy),
        .vf_done    (vf_done),
        .v_mbd      (v_mbd),
        .v_tile     (v_tile)
    );

    assign vpu_using_mem = vf_busy;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            curr_state    <= v_IDLE;
            row_idx       <= '0;
            vf_start      <= 1'b0;
            vpu_row_start <= 1'b0;
            vpu_done      <= 1'b0;

            for (int j = 0; j < SA_ROWS; j++) begin
                m_i[j]         <= NEG_INF;
                m_i_minus_1[j] <= NEG_INF;
                d_i[j]         <= '0;
                d_i_minus_1[j] <= '0;
            end

            for (int i = 0; i < D_MODEL; i++) begin
                for (int j = 0; j < SA_ROWS; j++) begin
                    o_i[j][i]         <= '0;
                    o_i_minus_1[j][i] <= '0;
                    o_norm[j][i]      <= '0;
                end
            end

            for (int j = 0; j < SA_ROWS; j++) begin
                for (int i = 0; i < D_MODEL; i++)
                    O_N[j][i] <= '0;
            end

            in_m_i         <= NEG_INF;
            in_m_i_minus_1 <= NEG_INF;
            in_d_i         <= '0;
            in_d_i_minus_1 <= '0;

            for (int i = 0; i < D_MODEL; i++) begin
                in_o_i[i]         <= '0;
                in_o_i_minus_1[i] <= '0;
            end
        end else begin
            vf_start      <= 1'b0;
            vpu_row_start <= 1'b0;
            vpu_done      <= 1'b0;

            case (curr_state)

                // Wait for a new score tile.
                v_IDLE: begin
                    if (vpu_start) begin
                        row_idx <= '0;
                        x_reg   <= scores;

                        // Reset running state for the first K/V tile of a Q batch.
                        if (first_kv) begin
                            for (int r = 0; r < SA_ROWS; r++) begin
                                m_i[r]         <= NEG_INF;
                                m_i_minus_1[r] <= NEG_INF;
                                d_i[r]         <= '0;
                                d_i_minus_1[r] <= '0;

                                for (int d = 0; d < D_MODEL; d++) begin
                                    o_i[r][d]         <= '0;
                                    o_i_minus_1[r][d] <= '0;
                                end
                            end
                        end

                        curr_state <= v_FETCH_START;
                    end
                end

                // Start fetching the current V tile.
                v_FETCH_START: begin
                    if (!vf_busy) begin
                        vf_start   <= 1'b1;
                        curr_state <= v_FETCH_WAIT;
                    end
                end

                // Wait until the complete V tile has been fetched.
                v_FETCH_WAIT: begin
                    if (vf_done) begin
                        V_reg      <= v_tile;
                        curr_state <= v_ROW_PREP;
                    end
                end

                // Load the running state for the current attention row.
                v_ROW_PREP: begin
                    for (int j = 0; j < SA_COLS; j++)
                        x_i[j] <= x_reg[row_idx][j];

                    in_m_i         <= m_i[row_idx];
                    in_m_i_minus_1 <= m_i_minus_1[row_idx];
                    in_d_i         <= d_i[row_idx];
                    in_d_i_minus_1 <= d_i_minus_1[row_idx];
                    in_o_i         <= o_i[row_idx];
                    in_o_i_minus_1 <= o_i_minus_1[row_idx];

                    curr_state <= v_ROW_START;
                end

                // Start the row processing unit.
                v_ROW_START: begin
                    if (!vpu_row_busy) begin
                        vpu_row_start <= 1'b1;
                        curr_state    <= v_ROW_WAIT;
                    end
                end

                // Save the updated state when the current row completes.
                v_ROW_WAIT: begin
                    if (vpu_row_done) begin
                        m_i[row_idx]         <= out_m_i;
                        m_i_minus_1[row_idx] <= out_m_i_minus_1;
                        d_i[row_idx]         <= out_d_i;
                        d_i_minus_1[row_idx] <= out_d_i_minus_1;

                        for (int d = 0; d < D_MODEL; d++) begin
                            o_i[row_idx][d]         <= out_o_i[d];
                            o_i_minus_1[row_idx][d] <= out_o_i_minus_1[d];
                            o_norm[row_idx][d]      <= out_o_norm[d];

                            // Temporary integer conversion. Replace with the
                            // selected rounding, saturation, and scaling policy.
                            O_N[row_idx][d] <= operand_t'(out_o_norm[d] >>> FRAC_BITS);
                        end

                        if (row_idx == ROW_IDX_W'(SA_ROWS-1))
                            curr_state <= v_DONE;
                        else begin
                            row_idx    <= row_idx + 1'b1;
                            curr_state <= v_ROW_PREP;
                        end
                    end
                end

                // Pulse completion after every row has been processed.
                v_DONE: begin
                    vpu_done   <= 1'b1;
                    curr_state <= v_IDLE;
                end

                default:
                    curr_state <= v_IDLE;

            endcase
        end
    end

endmodule