`timescale 1ns / 1ps
import fa_pkg::*;

module tb_mxu;
    // =====================================================
    // Storage depth: must cover the largest offset+k used
    // across all cases (k=16 for case 1, offsets up to 8 for case 3)
    // =====================================================
    localparam int MAX_K = D_MODEL; // 16
    localparam int TIMEOUT_CYCLES = 4 * (MAX_K + 2*SA_COLS);

    // =====================================================
    // DUT IO
    // =====================================================
    logic clk;
    logic rst_n;
    logic start;
    logic done;
    mxu_cmd_t cmd;
    logic mxu_reading_ram;

    operand_bus_t in_a;
    operand_bus_t in_b;
    k_dim_t a_k_rd_idx;
    k_dim_t b_k_rd_idx;

    accumulator_t c [0:SA_ROWS-1][0:SA_COLS-1];
    accumulator_t row_max [0:SA_ROWS-1];

    // =====================================================
    // DUT
    // =====================================================
    mxu dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .mxu_start       (start),
        .mxu_done        (done),
        .mxu_cmd         (cmd),
        .mxu_reading_ram (mxu_reading_ram),
        .in_a            (in_a),
        .in_b            (in_b),
        .a_k_rd_idx    (a_k_rd_idx),
        .b_k_rd_idx    (b_k_rd_idx),
        .c               (c),
        .row_max         (row_max)
    );

    // =====================================================
    // CLOCK
    // =====================================================
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // =====================================================
    // BACKING STORE (sized to MAX_K so any k/offset combo we
    // test can be indexed directly by a_k_rd_idx/b_k_rd_idx,
    // which are assumed to already be absolute indices)
    // =====================================================
    operand_t A_MEM [0:SA_ROWS-1][0:MAX_K-1];
    operand_t B_MEM [0:MAX_K-1][0:SA_COLS-1];

    accumulator_t golden [0:SA_ROWS-1][0:SA_COLS-1];
    accumulator_t golden_row_max [0:SA_ROWS-1];

    int errors;

    // =====================================================
    // SRAM MODEL
    // =====================================================
    function automatic operand_bus_t pack_a_column(input k_dim_t k_idx);
        operand_bus_t packed_word;
        begin
            packed_word = '0;
            for (int row = 0; row < SA_ROWS; row++) begin
                packed_word[8*row +: 8] = A_MEM[row][k_idx];
            end
            pack_a_column = packed_word;
        end
    endfunction

    function automatic operand_bus_t pack_b_row(input k_dim_t k_idx);
        operand_bus_t packed_word;
        begin
            packed_word = '0;
            for (int col = 0; col < SA_COLS; col++) begin
                packed_word[8*col +: 8] = B_MEM[k_idx][col];
            end
            pack_b_row = packed_word;
        end
    endfunction

    logic [OPERAND_BUS_W-1:0] a_reg, b_reg;

    always_ff @(posedge clk) begin
        a_reg <= pack_a_column(a_k_rd_idx);
        b_reg <= pack_b_row(b_k_rd_idx);
    end

    assign in_a = a_reg;
    assign in_b = b_reg;

    // =====================================================
    // DUT IO DRIVE TASKS
    // =====================================================
    task automatic apply_reset;
        begin
            rst_n <= 1'b0;
            start <= 1'b0;
            repeat (3) @(posedge clk);
            rst_n <= 1'b1;
            @(posedge clk);
        end
    endtask

    task automatic pulse_start;
        begin
            @(negedge clk);
            start <= 1'b1;
            @(negedge clk);
            start <= 1'b0;
        end
    endtask

    task automatic wait_for_done;
        int cycle_count;
        begin
            cycle_count = 0;
            while (!done && cycle_count < TIMEOUT_CYCLES) begin
                @(posedge clk);
                cycle_count++;
            end
            if (cycle_count >= TIMEOUT_CYCLES) begin
                $display("\nFAIL: TIMEOUT waiting for done after %0d cycles", cycle_count);
                errors++;
            end
        end
    endtask

    // =====================================================
    // INITIALIZE BACKING STORE (single formula, full MAX_K depth,
    // reused across all cases regardless of which k/offset slice
    // a given case actually reads)
    // =====================================================
    task automatic init_memories;
        begin
            for (int row = 0; row < SA_ROWS; row++) begin
                for (int k = 0; k < MAX_K; k++) begin
                    A_MEM[row][k] = operand_t'(-4 + row + (k % 5));
                end
            end
            for (int k = 0; k < MAX_K; k++) begin
                for (int col = 0; col < SA_COLS; col++) begin
                    B_MEM[k][col] = operand_t'(3 - col + (k % 7));
                end
            end
        end
    endtask

    // =====================================================
    // CMD BUILDER
    // =====================================================
    task automatic build_cmd(
        input m_dim_t m,
        input n_dim_t n,
        input k_dim_t k,
        input m_dim_t a_m_offset,
        input k_dim_t a_k_offset,
        input k_dim_t b_k_offset,
        input n_dim_t b_n_offset,
        input m_dim_t c_m_offset,
        input n_dim_t c_n_offset
    );
        begin
            cmd.m           = m;
            cmd.n           = n;
            cmd.k           = k;
            cmd.a_m_offset  = a_m_offset;
            cmd.a_k_offset  = a_k_offset;
            cmd.b_k_offset  = b_k_offset;
            cmd.b_n_offset  = b_n_offset;
            cmd.c_m_offset  = c_m_offset;
            cmd.c_n_offset  = c_n_offset;
        end
    endtask

    // =====================================================
    // GOLDEN MODEL
    // clear_first: zero golden before accumulating this slice
    // (false) lets the caller build multi-call accumulation,
    // matching what the DUT is expected to do when it does not
    // clear its accumulator between calls.
    // =====================================================
    task automatic compute_golden_slice(
        input k_dim_t a_k_offset,
        input k_dim_t b_k_offset,
        input k_dim_t k_len,
        input bit     clear_first
    );
        begin
            if (clear_first) begin
                for (int row = 0; row < SA_ROWS; row++)
                    for (int col = 0; col < SA_COLS; col++)
                        golden[row][col] = '0;
            end
            for (int row = 0; row < SA_ROWS; row++) begin
                for (int col = 0; col < SA_COLS; col++) begin
                    for (int kk = 0; kk < k_len; kk++) begin
                        golden[row][col] += accumulator_t'(
                            $signed(A_MEM[row][a_k_offset + kk]) *
                            $signed(B_MEM[b_k_offset + kk][col])
                        );
                    end
                end
            end
        end
    endtask

    task automatic compute_golden_row_max;
        begin
            for (int row = 0; row < SA_ROWS; row++) begin
                golden_row_max[row] = golden[row][0];
                for (int col = 1; col < SA_COLS; col++) begin
                    if ($signed(golden[row][col]) > $signed(golden_row_max[row]))
                        golden_row_max[row] = golden[row][col];
                end
            end
        end
    endtask

    // =====================================================
    // PRINT HELPERS
    // =====================================================
    task automatic print_golden;
        begin
            $display("\n===== GOLDEN C TILE =====");
            for (int row = 0; row < SA_ROWS; row++) begin
                $write("row %0d: ", row);
                for (int col = 0; col < SA_COLS; col++) $write("%0d ", golden[row][col]);
                $write("\n");
            end
            $display("\n===== GOLDEN ROW MAX =====");
            for (int row = 0; row < SA_ROWS; row++)
                $display("row %0d: %0d", row, $signed(golden_row_max[row]));
        end
    endtask

    task automatic print_dut_result;
        begin
            $display("\n===== DUT C TILE =====");
            for (int row = 0; row < SA_ROWS; row++) begin
                $write("row %0d: ", row);
                for (int col = 0; col < SA_COLS; col++) $write("%0d ", c[row][col]);
                $write("\n");
            end
            $display("\n===== DUT ROW MAX =====");
            for (int row = 0; row < SA_ROWS; row++)
                $display("row %0d: %0d", row, $signed(row_max[row]));
        end
    endtask

    // =====================================================
    // CHECK RESULT
    // =====================================================
    task automatic check_result;
        begin
            $display("\n===== SELF CHECK =====");
            for (int row = 0; row < SA_ROWS; row++) begin
                for (int col = 0; col < SA_COLS; col++) begin
                    if (c[row][col] !== golden[row][col]) begin
                        $display("FAIL C[%0d][%0d]: DUT=%0d GOLD=%0d",
                                 row, col, c[row][col], golden[row][col]);
                        errors++;
                    end else begin
                        $display("PASS C[%0d][%0d] = %0d", row, col, c[row][col]);
                    end
                end
            end
            for (int row = 0; row < SA_ROWS; row++) begin
                if (row_max[row] !== golden_row_max[row]) begin
                    $display("FAIL ROW_MAX[%0d]: DUT=%0d GOLD=%0d",
                             row, $signed(row_max[row]), $signed(golden_row_max[row]));
                    errors++;
                end else begin
                    $display("PASS ROW_MAX[%0d] = %0d", row, $signed(row_max[row]));
                end
            end
        end
    endtask

    task automatic check_idle_protocol;
        begin
            if (done !== 1'b0) begin
                $display("FAIL: done asserted while idle, before start");
                errors++;
            end
        end
    endtask

    // =====================================================
    // CASE RUNNER: builds cmd, pulses start, waits done
    // =====================================================
    task automatic run_matmul(
        input m_dim_t m, input n_dim_t n, input k_dim_t k,
        input k_dim_t a_k_offset, input k_dim_t b_k_offset
    );
        begin
            build_cmd(m, n, k, m_dim_t'(0), a_k_offset, b_k_offset, n_dim_t'(0),
                      m_dim_t'(0), n_dim_t'(0));
            pulse_start();
            wait_for_done();
        end
    endtask

    // =====================================================
    // MAIN TEST
    // =====================================================
    initial begin
        errors = 0;
        init_memories();
        apply_reset();
        check_idle_protocol();

        // ---------- Case 1: 8x16x8 (full QK^T tile) ----------
        $display("\n===== CASE 1: 8x16x8 (QK^T) =====");
        run_matmul(SA_ROWS, SA_COLS, D_MODEL, k_dim_t'(0), k_dim_t'(0));
        compute_golden_slice(k_dim_t'(0), k_dim_t'(0), D_MODEL, 1'b1);
        compute_golden_row_max();
        print_golden();
        print_dut_result();
        check_result();

        // ---------- Case 2: 8x8x8 (simple GEMM sanity) ----------
        apply_reset();
        $display("\n===== CASE 2: 8x8x8 (simple GEMM) =====");
        run_matmul(SA_ROWS, SA_COLS, 8, k_dim_t'(0), k_dim_t'(0));
        compute_golden_slice(k_dim_t'(0), k_dim_t'(0), 8, 1'b1);
        compute_golden_row_max();
        print_golden();
        print_dut_result();
        check_result();

        // ---------- Case 3: two consecutive 8x8x8 (O = P@V, two V tiles) ----------
        apply_reset();
        $display("\n===== CASE 3a: 8x8x8, b_k_offset=0 (V tile 0) =====");
        run_matmul(SA_ROWS, SA_COLS, 8, k_dim_t'(0), k_dim_t'(0));
        compute_golden_slice(k_dim_t'(0), k_dim_t'(0), 8, 1'b1); // clear + accumulate

        $display("\n===== CASE 3b: 8x8x8, b_k_offset=8 (V tile 1, no reset) =====");
        run_matmul(SA_ROWS, SA_COLS, 8, k_dim_t'(0), k_dim_t'(8));
        compute_golden_slice(k_dim_t'(0), k_dim_t'(8), 8, 1'b0); // accumulate onto existing golden

        compute_golden_row_max();
        print_golden();
        print_dut_result();
        check_result();

        if (errors == 0)
            $display("\nTEST PASSED");
        else
            $display("\nTEST FAILED: %0d mismatches", errors);
        $finish;
    end
endmodule