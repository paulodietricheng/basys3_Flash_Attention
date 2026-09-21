`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/05/2026 17:10:26 AM
// Design Name: 
// Module Name: dma
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

import fa_pkg::*;

// ============================================================================
// DMA Channel
//
// Transfers an INT8 rows x cols matrix between:
//
//   HBM : 8 independent 32-bit channels
//   SRAM: 2 independent 32-bit ports
//
// HBM layout:
//   - Row-major
//   - 4 INT8 dimensions per 32-bit word
//   - 8 rows are transferred in parallel
//
// SRAM layout:
//
//   transpose = 0:
//       Row-major.
//       One complete HBM word is stored per SRAM word.
//
//   transpose = 1:
//       Dimension-major.
//       Each SRAM word contains four rows for one dimension:
//
//           [31:24] = row + 3
//           [23:16] = row + 2
//           [15: 8] = row + 1
//           [ 7: 0] = row
//
// The DMA is intentionally simple:
//
// HBM -> SRAM:
//   HBM_READ
//       |
//       v
//   ACCUM              Capture 8 x 32-bit HBM words
//       |
//       v
//   SRAM_WRITE x 4     Drain 32-bit registers
//
// SRAM -> HBM:
//   SRAM_READ x 4      Assemble 8 x 32-bit registers
//       |
//       v
//   ACCUM_REV
//       |
//       v
//   HBM_WRITE          Write 8 HBM channels in parallel
//
// HBM read latency:
//   1 cycle
//
// SRAM read latency:
//   1 cycle
//
// Both memory interfaces are assumed synchronous.
// ============================================================================

module dma_ch (

    input  logic clk,
    input  logic rst_n,

    // ========================================================================
    // Request
    // ========================================================================

    input  dma_rq_t dma_rq,
    input  logic    dma_start,

    output logic dma_busy,
    output logic dma_done,

    // ========================================================================
    // HBM interface
    //
    // 8 channels, each 32 bits wide.
    //
    // hbm_we = 0 : HBM read
    // hbm_we = 1 : HBM write
    // ========================================================================

    output logic hbm_we,

    output logic [HBM_ADDR_W-1:0] hbm_addr [8],
    output bram_word_t            hbm_din  [8],

    input  bram_word_t            hbm_dout [8],
    input logic                   hbm_rvalid,

    // ========================================================================
    // SRAM interface
    //
    // 2 independent 32-bit ports.
    //
    // sram_we = 0 : SRAM read
    // sram_we = 1 : SRAM write
    // ========================================================================

    output logic sram_we,

    output logic [SRAM_ADDR_W-1:0] sram_addr [2],
    output sram_word_t             sram_din  [2],

    input sram_word_t              sram_dout [2],

    // ========================================================================
    // Status
    // ========================================================================

    output logic dma_using_mem
);


    // =========================================================================
    // Parameters
    // =========================================================================

    localparam int HBM_LANES            = 8;
    localparam int SRAM_PORTS           = 2;

    localparam int HBM_WPA              =
        BRAM_WORD_W / OPERAND_W;

    localparam int ROWS_PER_HBM_BURST   =
        HBM_LANES;

    localparam int ROWS_PER_SRAM_WORD   =
        SRAM_WORD_W / OPERAND_W;


    // =========================================================================
    // State machine
    // =========================================================================

    typedef enum logic [3:0] {
        d_IDLE,

        d_SETUP,

        // HBM -> SRAM
        d_HBM_READ,
        d_ACCUM,
        d_SRAM_WRITE,

        // SRAM -> HBM
        d_SRAM_READ,
        d_ACCUM_REV,
        d_HBM_WRITE,

        d_DONE
    } dma_state_t;

    dma_state_t curr_state;


    // =========================================================================
    // Latched request
    // =========================================================================

    dma_rq_t rq_reg;


    // =========================================================================
    // Geometry
    //
    // words_per_row:
    //     ceil(cols / 4)
    //
    // row_bursts:
    //     ceil(rows / 8)
    //
    // sram_row_groups:
    //     ceil(rows / 4)
    //
    // The last quantity is only used for transpose mode.
    // =========================================================================

    logic [31:0] words_per_row;
    logic [31:0] row_bursts;
    logic [31:0] sram_row_groups;


    // =========================================================================
    // Transfer counters
    // =========================================================================

    // Which group of 8 rows are being transferred.
    logic [31:0] row_burst_idx;

    // Which group of 4 dimensions is being transferred.
    logic [31:0] word_group_idx;

    // 0..3:
    //
    // HBM -> SRAM:
    //     which byte/dimension is being drained
    //
    // SRAM -> HBM:
    //     which byte/dimension is being assembled
    //
    logic [1:0] subcycle_idx;


    // =========================================================================
    // Register file
    //
    // reg_file[i] contains the 32-bit HBM word belonging to row i of the
    // current 8-row burst.
    //
    // Byte ordering:
    //
    //   [ 7: 0] = dimension 4k + 0
    //   [15: 8] = dimension 4k + 1
    //   [23:16] = dimension 4k + 2
    //   [31:24] = dimension 4k + 3
    // =========================================================================

    logic [BRAM_WORD_W-1:0] reg_file [HBM_LANES];


    // =========================================================================
    // HBM write enable
    // =========================================================================

    assign hbm_we =
        (curr_state == d_HBM_WRITE);


    // =========================================================================
    // SRAM write enable
    // =========================================================================

    assign sram_we =
        (curr_state == d_SRAM_WRITE);


    // =========================================================================
    // Status
    // =========================================================================

    assign dma_busy =
        (curr_state != d_IDLE) &&
        (curr_state != d_DONE);

    assign dma_done =
        (curr_state == d_DONE);

    assign dma_using_mem =
        (curr_state != d_IDLE) &&
        (curr_state != d_DONE);


    // =========================================================================
    // Combinational datapath
    // =========================================================================

    always_comb begin

        // ---------------------------------------------------------------------
        // Safe defaults
        // ---------------------------------------------------------------------

        for (int i = 0; i < HBM_LANES; i++) begin
            hbm_addr[i] = '0;
            hbm_din[i]  = '0;
        end

        for (int i = 0; i < SRAM_PORTS; i++) begin
            sram_addr[i] = '0;
            sram_din[i]  = '0;
        end


        // =====================================================================
        // HBM interface
        // =====================================================================

        case (curr_state)

            // -----------------------------------------------------------------
            // HBM READ
            //
            // Every channel gets the same local address.
            //
            // Channel i represents row:
            //
            //     row_burst_idx * 8 + i
            //
            // in the current burst.
            // -----------------------------------------------------------------

            d_HBM_READ,
            d_ACCUM: begin

                for (int i = 0; i < HBM_LANES; i++) begin

                    hbm_addr[i] =
                        rq_reg.hbm_base_addr
                        + (row_burst_idx * words_per_row)
                        + word_group_idx;

                end

            end


            // -----------------------------------------------------------------
            // HBM WRITE
            // -----------------------------------------------------------------

            d_HBM_WRITE: begin

                for (int i = 0; i < HBM_LANES; i++) begin

                    hbm_addr[i] =
                        rq_reg.hbm_base_addr
                        + (row_burst_idx * words_per_row)
                        + word_group_idx;

                    hbm_din[i] =
                        reg_file[i];

                end

            end

            default: begin
            end

        endcase


        // =====================================================================
        // SRAM interface
        // =====================================================================

        case (curr_state)

            // =================================================================
            // HBM -> SRAM
            // =================================================================

            d_SRAM_WRITE: begin

                if (rq_reg.transpose) begin

                    // ---------------------------------------------------------
                    // TRANSPOSED
                    //
                    // dimension:
                    //
                    //     word_group_idx * 4 + subcycle_idx
                    //
                    // Each SRAM word contains four rows.
                    //
                    // Two SRAM ports cover rows:
                    //
                    //     port 0: rows 0..3
                    //     port 1: rows 4..7
                    //
                    // Address:
                    //
                    //     base
                    //       + dimension * ceil(rows/4)
                    //       + row_group
                    //
                    // where each HBM burst corresponds to two SRAM row groups.
                    // ---------------------------------------------------------

                    sram_addr[0] =
                        rq_reg.sram_base_addr
                        + (
                            (
                                word_group_idx * HBM_WPA
                                + subcycle_idx
                            )
                            * sram_row_groups
                        )
                        + (row_burst_idx * 2);

                    sram_addr[1] =
                        rq_reg.sram_base_addr
                        + (
                            (
                                word_group_idx * HBM_WPA
                                + subcycle_idx
                            )
                            * sram_row_groups
                        )
                        + (row_burst_idx * 2)
                        + 1;


                    // ---------------------------------------------------------
                    // Pack rows 0..3.
                    //
                    // SRAM byte 0 = row 0
                    // SRAM byte 1 = row 1
                    // SRAM byte 2 = row 2
                    // SRAM byte 3 = row 3
                    // ---------------------------------------------------------

                    sram_din[0] = {
                        reg_file[3][subcycle_idx * OPERAND_W +: OPERAND_W],
                        reg_file[2][subcycle_idx * OPERAND_W +: OPERAND_W],
                        reg_file[1][subcycle_idx * OPERAND_W +: OPERAND_W],
                        reg_file[0][subcycle_idx * OPERAND_W +: OPERAND_W]
                    };


                    // ---------------------------------------------------------
                    // Pack rows 4..7.
                    // ---------------------------------------------------------

                    sram_din[1] = {
                        reg_file[7][subcycle_idx * OPERAND_W +: OPERAND_W],
                        reg_file[6][subcycle_idx * OPERAND_W +: OPERAND_W],
                        reg_file[5][subcycle_idx * OPERAND_W +: OPERAND_W],
                        reg_file[4][subcycle_idx * OPERAND_W +: OPERAND_W]
                    };

                end
                else begin

                    // ---------------------------------------------------------
                    // NON-TRANSPOSED
                    //
                    // Two complete HBM words are written per cycle.
                    //
                    // subcycle 0 -> rows 0,1
                    // subcycle 1 -> rows 2,3
                    // subcycle 2 -> rows 4,5
                    // subcycle 3 -> rows 6,7
                    // ---------------------------------------------------------

                    sram_addr[0] =
                        rq_reg.sram_base_addr
                        + (
                            (
                                row_burst_idx * ROWS_PER_HBM_BURST
                                + subcycle_idx * 2
                            )
                            * words_per_row
                        )
                        + word_group_idx;

                    sram_addr[1] =
                        rq_reg.sram_base_addr
                        + (
                            (
                                row_burst_idx * ROWS_PER_HBM_BURST
                                + subcycle_idx * 2
                                + 1
                            )
                            * words_per_row
                        )
                        + word_group_idx;


                    sram_din[0] =
                        reg_file[subcycle_idx * 2];

                    sram_din[1] =
                        reg_file[subcycle_idx * 2 + 1];

                end

            end


            // =================================================================
            // SRAM -> HBM
            // =================================================================

            d_SRAM_READ: begin

                if (rq_reg.transpose) begin

                    // ---------------------------------------------------------
                    // TRANSPOSED
                    //
                    // Read one dimension per cycle.
                    //
                    // The two SRAM ports read:
                    //
                    //     rows 0..3
                    //     rows 4..7
                    // ---------------------------------------------------------

                    sram_addr[0] =
                        rq_reg.sram_base_addr
                        + (
                            (
                                word_group_idx * HBM_WPA
                                + subcycle_idx
                            )
                            * sram_row_groups
                        )
                        + (row_burst_idx * 2);

                    sram_addr[1] =
                        rq_reg.sram_base_addr
                        + (
                            (
                                word_group_idx * HBM_WPA
                                + subcycle_idx
                            )
                            * sram_row_groups
                        )
                        + (row_burst_idx * 2)
                        + 1;

                end
                else begin

                    // ---------------------------------------------------------
                    // NON-TRANSPOSED
                    //
                    // Read two complete row words per cycle.
                    // ---------------------------------------------------------

                    sram_addr[0] =
                        rq_reg.sram_base_addr
                        + (
                            (
                                row_burst_idx * ROWS_PER_HBM_BURST
                                + subcycle_idx * 2
                            )
                            * words_per_row
                        )
                        + word_group_idx;

                    sram_addr[1] =
                        rq_reg.sram_base_addr
                        + (
                            (
                                row_burst_idx * ROWS_PER_HBM_BURST
                                + subcycle_idx * 2
                                + 1
                            )
                            * words_per_row
                        )
                        + word_group_idx;

                end

            end

            default: begin
            end

        endcase

    end


    // =========================================================================
    // Sequential control and datapath
    // =========================================================================

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            curr_state <= d_IDLE;

            rq_reg <= '0;

            words_per_row   <= '0;
            row_bursts      <= '0;
            sram_row_groups <= '0;

            row_burst_idx  <= '0;
            word_group_idx <= '0;
            subcycle_idx   <= '0;

            for (int i = 0; i < HBM_LANES; i++)
                reg_file[i] <= '0;

        end
        else begin

            case (curr_state)

                // =============================================================
                // IDLE
                // =============================================================

                d_IDLE: begin

                    if (dma_start) begin

                        // -----------------------------------------------------
                        // Latch request.
                        // -----------------------------------------------------

                        rq_reg <= dma_rq;


                        // -----------------------------------------------------
                        // ceil(cols / 4)
                        // -----------------------------------------------------

                        words_per_row <=
                            (dma_rq.cols + HBM_WPA - 1)
                            / HBM_WPA;


                        // -----------------------------------------------------
                        // ceil(rows / 8)
                        // -----------------------------------------------------

                        row_bursts <=
                            (
                                dma_rq.rows
                                + ROWS_PER_HBM_BURST
                                - 1
                            )
                            / ROWS_PER_HBM_BURST;


                        // -----------------------------------------------------
                        // ceil(rows / 4)
                        // -----------------------------------------------------

                        sram_row_groups <=
                            (
                                dma_rq.rows
                                + ROWS_PER_SRAM_WORD
                                - 1
                            )
                            / ROWS_PER_SRAM_WORD;


                        row_burst_idx  <= '0;
                        word_group_idx <= '0;
                        subcycle_idx   <= '0;

                        curr_state <= d_SETUP;

                    end

                end


                // =============================================================
                // SETUP
                // =============================================================

                d_SETUP: begin

                    if ((rq_reg.rows == 0) ||
                        (rq_reg.cols == 0)) begin

                        curr_state <= d_DONE;

                    end
                    else if (rq_reg.direction == 1'b0) begin

                        // HBM -> SRAM

                        curr_state <= d_HBM_READ;

                    end
                    else begin

                        // SRAM -> HBM
                        //
                        // Start with an empty register file so that unused
                        // rows/dimensions remain zero.

                        for (int i = 0; i < HBM_LANES; i++)
                            reg_file[i] <= '0;

                        curr_state <= d_SRAM_READ;

                    end

                end


                // =============================================================
                // HBM READ
                //
                // Address is presented for this cycle.
                //
                // The HBM model returns data during the following d_ACCUM
                // state.
                // =============================================================

                d_HBM_READ: begin

                    curr_state <= d_ACCUM;

                end


                // =============================================================
                // HBM ACCUMULATION
                // =============================================================

                d_ACCUM: begin

                    if (hbm_rvalid) begin

                        // -----------------------------------------------------
                        // Capture all 8 HBM words.
                        //
                        // Invalid rows and invalid dimensions in the final
                        // partial burst are explicitly zeroed.
                        // -----------------------------------------------------

                        for (int i = 0; i < HBM_LANES; i++) begin

                            if (
                                (row_burst_idx * ROWS_PER_HBM_BURST + i)
                                < rq_reg.rows
                            ) begin

                                for (int b = 0; b < HBM_WPA; b++) begin

                                    if (
                                        (word_group_idx * HBM_WPA + b)
                                        < rq_reg.cols
                                    ) begin

                                        reg_file[i][
                                            b * OPERAND_W +: OPERAND_W
                                        ] <=
                                            hbm_dout[i][
                                                b * OPERAND_W +: OPERAND_W
                                            ];

                                    end
                                    else begin

                                        reg_file[i][
                                            b * OPERAND_W +: OPERAND_W
                                        ] <= '0;

                                    end

                                end

                            end
                            else begin

                                reg_file[i] <= '0;

                            end

                        end

                        subcycle_idx <= '0;

                        curr_state <= d_SRAM_WRITE;

                    end

                end


                // =============================================================
                // SRAM WRITE
                //
                // Four cycles are required to drain the 8 HBM registers.
                // =============================================================

                d_SRAM_WRITE: begin

                    if (subcycle_idx == HBM_WPA - 1) begin

                        subcycle_idx <= '0;


                        // -----------------------------------------------------
                        // More dimension groups in this row burst?
                        // -----------------------------------------------------

                        if (word_group_idx < words_per_row - 1) begin

                            word_group_idx <= word_group_idx + 1;

                            curr_state <= d_HBM_READ;

                        end


                        // -----------------------------------------------------
                        // More row bursts?
                        // -----------------------------------------------------

                        else if (row_burst_idx < row_bursts - 1) begin

                            word_group_idx <= '0;

                            row_burst_idx <= row_burst_idx + 1;

                            curr_state <= d_HBM_READ;

                        end


                        // -----------------------------------------------------
                        // Entire transfer complete.
                        // -----------------------------------------------------

                        else begin

                            curr_state <= d_DONE;

                        end

                    end
                    else begin

                        subcycle_idx <= subcycle_idx + 1;

                    end

                end


                // =============================================================
                // SRAM READ
                //
                // Address is presented for one cycle.
                //
                // SRAM response is consumed in d_ACCUM_REV.
                // =============================================================

                d_SRAM_READ: begin

                    curr_state <= d_ACCUM_REV;

                end


                // =============================================================
                // SRAM ACCUMULATION / RECONSTRUCTION
                // =============================================================

                d_ACCUM_REV: begin

                    if (rq_reg.transpose) begin

                        // -----------------------------------------------------
                        // TRANSPOSED
                        //
                        // SRAM port 0 contains rows 0..3.
                        // SRAM port 1 contains rows 4..7.
                        //
                        // The selected byte is inserted into the corresponding
                        // byte position of each reg_file entry.
                        // -----------------------------------------------------

                        for (int r = 0; r < ROWS_PER_SRAM_WORD; r++) begin

                            if (
                                (
                                    row_burst_idx
                                    * ROWS_PER_HBM_BURST
                                    + r
                                )
                                < rq_reg.rows
                            ) begin

                                reg_file[r][
                                    subcycle_idx * OPERAND_W
                                    +: OPERAND_W
                                ] <=
                                    sram_dout[0][
                                        r * OPERAND_W
                                        +: OPERAND_W
                                    ];

                            end

                        end


                        for (int r = 0; r < ROWS_PER_SRAM_WORD; r++) begin

                            if (
                                (
                                    row_burst_idx
                                    * ROWS_PER_HBM_BURST
                                    + ROWS_PER_SRAM_WORD
                                    + r
                                )
                                < rq_reg.rows
                            ) begin

                                reg_file[
                                    ROWS_PER_SRAM_WORD + r
                                ][
                                    subcycle_idx * OPERAND_W
                                    +: OPERAND_W
                                ] <=
                                    sram_dout[1][
                                        r * OPERAND_W
                                        +: OPERAND_W
                                    ];

                            end

                        end

                    end
                    else begin

                        // -----------------------------------------------------
                        // NON-TRANSPOSED
                        //
                        // Two complete HBM words are reconstructed per cycle.
                        // -----------------------------------------------------

                        if (
                            row_burst_idx * ROWS_PER_HBM_BURST
                            + subcycle_idx * 2
                            < rq_reg.rows
                        ) begin

                            reg_file[subcycle_idx * 2] <=
                                sram_dout[0];

                        end
                        else begin

                            reg_file[subcycle_idx * 2] <= '0;

                        end


                        if (
                            row_burst_idx * ROWS_PER_HBM_BURST
                            + subcycle_idx * 2
                            + 1
                            < rq_reg.rows
                        ) begin

                            reg_file[subcycle_idx * 2 + 1] <=
                                sram_dout[1];

                        end
                        else begin

                            reg_file[subcycle_idx * 2 + 1] <= '0;

                        end

                    end


                    // ---------------------------------------------------------
                    // Four SRAM reads have assembled the complete HBM burst.
                    // ---------------------------------------------------------

                    if (subcycle_idx == HBM_WPA - 1) begin

                        subcycle_idx <= '0;

                        curr_state <= d_HBM_WRITE;

                    end
                    else begin

                        subcycle_idx <= subcycle_idx + 1;

                        curr_state <= d_SRAM_READ;

                    end

                end


                // =============================================================
                // HBM WRITE
                // =============================================================

                d_HBM_WRITE: begin

                    // ---------------------------------------------------------
                    // More dimension groups?
                    // ---------------------------------------------------------

                    if (word_group_idx < words_per_row - 1) begin

                        word_group_idx <= word_group_idx + 1;

                        // Clear register file before assembling next word.

                        for (int i = 0; i < HBM_LANES; i++)
                            reg_file[i] <= '0;

                        curr_state <= d_SRAM_READ;

                    end


                    // ---------------------------------------------------------
                    // More row bursts?
                    // ---------------------------------------------------------

                    else if (row_burst_idx < row_bursts - 1) begin

                        word_group_idx <= '0;

                        row_burst_idx <= row_burst_idx + 1;

                        for (int i = 0; i < HBM_LANES; i++)
                            reg_file[i] <= '0;

                        curr_state <= d_SRAM_READ;

                    end


                    // ---------------------------------------------------------
                    // Transfer complete.
                    // ---------------------------------------------------------

                    else begin

                        curr_state <= d_DONE;

                    end

                end


                // =============================================================
                // DONE
                // =============================================================

                d_DONE: begin

                    curr_state <= d_IDLE;

                end


                // =============================================================
                // Safety
                // =============================================================

                default: begin

                    curr_state <= d_IDLE;

                end

            endcase

        end

    end

endmodule