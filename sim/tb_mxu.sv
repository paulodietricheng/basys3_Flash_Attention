`timescale 1ns / 1ps
import fa_pkg::*;

module tb_mxu;
    // =====================================================
    // Storage depth: must cover the largest offset+k used
    // across all cases (k=16 for case 1, offsets up to 8 for case 3)
    // =====================================================
    localparam int MAX_K = D_MODEL; // 16
    localparam int MAX_M = 3 * SA_ROWS;
    localparam int MAX_N = 3 * SA_COLS;
    localparam int TIMEOUT_CYCLES = 4 * (MAX_K + 2*SA_COLS);

    // =====================================================
    // DUT IO
    // =====================================================
    logic clk;
    logic rst_n;
    logic start;
    logic done;
    mxu_cmd_t cmd;
    mxu_cmd_t last_cmd; // Retain the command after pulse_start clears cmd.
    logic mxu_using_mem [2];

    operand_t in_a [SA_ROWS];
    operand_t in_b [SA_COLS];
    k_dim_t a_k_rd_idx;
    k_dim_t b_k_rd_idx;

    accumulator_t c [0:SA_ROWS-1][0:SA_COLS-1];

    // =====================================================
    // DUT
    // =====================================================
    mxu dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .mxu_start       (start),
        .mxu_done        (done),
        .mxu_cmd         (cmd),
        .mxu_using_mem (mxu_using_mem),
        .in_a            (in_a),
        .in_b            (in_b),
        .a_k_rd_idx    (a_k_rd_idx),
        .b_k_rd_idx    (b_k_rd_idx),
        .c               (c)
    );

    // =====================================================
    // CLOCK
    // =====================================================
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // =====================================================
    // BACKING STORE: three row tiles of A and three column tiles of B.
    // M/N offsets are element addresses in these larger matrices.
    // The DUT's K read indices are assumed to already include K offsets.
    // =====================================================
    operand_t A_MEM [0:MAX_M-1][0:MAX_K-1];
    operand_t B_MEM [0:MAX_K-1][0:MAX_N-1];

    accumulator_t golden [0:SA_ROWS-1][0:SA_COLS-1];

    int errors;

    // =====================================================
    // SRAM MODEL
    // =====================================================
    // Unpacked-array types so the functions return true unpacked arrays
    typedef operand_t operand_a_col_t [0:SA_ROWS-1];
    typedef operand_t operand_b_row_t [0:SA_COLS-1];

    // This interface exposes only K read indices. The testbench models
    // external tile selection using the command saved by run_matmul.
    // Lane 0 receives the first row/column of the selected memory tile.
    // This checks tile data/results, not an independent DUT M/N address bus.
    function automatic operand_a_col_t pack_a_column(input k_dim_t k_idx);
        operand_a_col_t word;
        for (int row = 0; row < SA_ROWS; row++) begin
            word[row] = A_MEM[int'(last_cmd.a_m_offset) + row][k_idx];
        end
        return word;
    endfunction

    function automatic operand_b_row_t pack_b_row(input k_dim_t k_idx);
        operand_b_row_t word;
        for (int col = 0; col < SA_COLS; col++) begin
            word[col] = B_MEM[k_idx][int'(last_cmd.b_n_offset) + col];
        end
        return word;
    endfunction

    operand_a_col_t a_reg;
    operand_b_row_t b_reg;

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
            cmd   <= '0;
            repeat (3) @(posedge clk);
            rst_n <= 1'b1;
            @(posedge clk);
        end
    endtask

    task automatic pulse_start(input mxu_cmd_t cmd_in);
    begin
        @(negedge clk);
        cmd   <= cmd_in;
        start <= 1'b1;

        @(negedge clk);
        start <= 1'b0;
        cmd   <= '0;
    end
    endtask

    task automatic wait_for_done;
        int cycle_count;
        begin
            cycle_count = 0;
            // Sample after the DUT's nonblocking assignments have settled.
            while (done !== 1'b1 && cycle_count < TIMEOUT_CYCLES) begin
                @(posedge clk);
                #1;
                cycle_count++;
            end
            if (done !== 1'b1)
                $fatal(1, "TIMEOUT waiting for done after %0d cycles", cycle_count);
        end
    endtask

    // =====================================================
    // INITIALIZE BACKING STORE (single formula, full MAX_K depth,
    // reused across all cases regardless of which k/offset slice
    // a given case actually reads)
    // =====================================================
    task automatic init_memories;
        begin
            for (int row = 0; row < MAX_M; row++) begin
                for (int k = 0; k < MAX_K; k++) begin
                    A_MEM[row][k] = operand_t'(-4 + row + (k % 5));
                end
            end
            for (int k = 0; k < MAX_K; k++) begin
                for (int col = 0; col < MAX_N; col++) begin
                    B_MEM[k][col] = operand_t'(3 - col + (k % 7));
                end
            end
        end
    endtask

    // =====================================================
    // GOLDEN MODEL
    // clear_first: zero golden before accumulating this slice
    // (false) lets the caller build multi-call accumulation,
    // matching what the DUT is expected to do when it does not
    // clear its accumulator between calls.
    // =====================================================
    // Contract under test:
    // C[i][j] +=
    //   sum(A[a_m_offset+i][a_k_offset+kk] *
    //       B[b_k_offset+kk][b_n_offset+j]), i<m, j<n, kk<k.
    // Source coordinates are global backing-memory addresses. C remains
    // an SA_ROWS x SA_COLS local result tile; C offsets are zero here.
    task automatic compute_golden_slice(
        input mxu_cmd_t op,
        input bit clear_first
    );
        begin
            if (clear_first) begin
                for (int row = 0; row < SA_ROWS; row++)
                    for (int col = 0; col < SA_COLS; col++)
                        golden[row][col] = '0;
            end
            for (int row = 0; row < int'(op.m); row++) begin
                for (int col = 0; col < int'(op.n); col++) begin
                    for (int kk = 0; kk < int'(op.k); kk++) begin
                        golden[row][col] += accumulator_t'(
                            $signed(A_MEM[int'(op.a_m_offset) + row]
                                         [int'(op.a_k_offset) + kk]) *
                            $signed(B_MEM[int'(op.b_k_offset) + kk]
                                         [int'(op.b_n_offset) + col])
                        );
                    end
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
        input m_dim_t m,
        input n_dim_t n,
        input k_dim_t k,
        input k_dim_t a_k_offset,
        input k_dim_t b_k_offset,
        input m_dim_t a_m_offset = '0,
        input n_dim_t b_n_offset = '0
    );
        mxu_cmd_t local_cmd;
    begin
        local_cmd = '0;

        local_cmd.m          = m;
        local_cmd.n          = n;
        local_cmd.k          = k;
        local_cmd.a_m_offset = a_m_offset;
        local_cmd.a_k_offset = a_k_offset;
        local_cmd.b_k_offset = b_k_offset;
        local_cmd.b_n_offset = b_n_offset;
        local_cmd.c_m_offset = '0;
        local_cmd.c_n_offset = '0;

        // Widen before adding, so packed dimension types cannot wrap.
        if (m == 0 || n == 0 || k == 0 ||
            int'(m) > SA_ROWS || int'(n) > SA_COLS ||
            int'(a_m_offset) + SA_ROWS > MAX_M ||
            int'(b_n_offset) + SA_COLS > MAX_N ||
            int'(a_k_offset) + int'(k) > MAX_K ||
            int'(b_k_offset) + int'(k) > MAX_K)
            $fatal(1, "Invalid test command: dimensions/offsets exceed backing store");

        last_cmd = local_cmd;
        pulse_start(local_cmd);
        wait_for_done();
    end
    endtask

    // =====================================================
    // MAIN TEST
    // =====================================================
    initial begin
        // The original tests require k=8 and b_k_offset=8.
        if (MAX_K < 16)
            $fatal(1, "These directed tests require MAX_K >= 16");
        // Offsets must address beyond one compute tile. Detect narrowing
        // in fa_pkg instead of silently truncating the third-tile address.
        if (int'(m_dim_t'(2 * SA_ROWS)) != 2 * SA_ROWS ||
            int'(n_dim_t'(2 * SA_COLS)) != 2 * SA_COLS)
            $fatal(1, "Widen m_dim_t/n_dim_t in fa_pkg to represent the backing-memory offsets");
        errors = 0;
        last_cmd = '0;
        init_memories();
        apply_reset();
        check_idle_protocol();

        // ---------- Case 1: 8x16x8 (full QK^T tile) ----------
        $display("\n===== CASE 1: 8x16x8 (QK^T) =====");
        run_matmul(SA_ROWS, SA_COLS, D_MODEL, k_dim_t'(0), k_dim_t'(0));
        compute_golden_slice(last_cmd, 1'b1);
        print_golden();
        print_dut_result();
        check_result();

        // ---------- Case 2: 8x8x8 (simple GEMM sanity) ----------
        apply_reset();
        $display("\n===== CASE 2: 8x8x8 (simple GEMM) =====");
        run_matmul(SA_ROWS, SA_COLS, 8, k_dim_t'(0), k_dim_t'(0));
        compute_golden_slice(last_cmd, 1'b1);
        print_golden();
        print_dut_result();
        check_result();

        // ---------- Case 3: two consecutive 8x8x8 (O = P@V, two V tiles) ----------
        apply_reset();
        $display("\n===== CASE 3a: 8x8x8, b_k_offset=0 (V tile 0) =====");
        run_matmul(SA_ROWS, SA_COLS, 8, k_dim_t'(0), k_dim_t'(0));
        compute_golden_slice(last_cmd, 1'b1); // clear + accumulate
        print_golden();
        print_dut_result();
        check_result();

        $display("\n===== CASE 3b: 8x8x8, b_k_offset=8 (V tile 1) =====");
        run_matmul(SA_ROWS, SA_COLS, 8, k_dim_t'(0), k_dim_t'(8));
        compute_golden_slice(last_cmd, 1'b0); // accumulate with offset
        print_golden();
        print_dut_result();
        check_result();

        // ---------- Case 4: A second row tile; B first column tile ----------
        apply_reset();
        $display("\n===== CASE 4: A second row tile; B first column tile =====");
        // Arguments: m, n, k, a_k, b_k, a_m, b_n.
        run_matmul(SA_ROWS, SA_COLS, 8, 0, 0,
                   m_dim_t'(SA_ROWS), n_dim_t'(0));
        compute_golden_slice(last_cmd, 1'b1);
        print_golden();
        print_dut_result();
        check_result();

        // ---------- Case 5: A first row tile; B second column tile ----------
        apply_reset();
        $display("\n===== CASE 5: A first row tile; B second column tile =====");
        // Arguments: m, n, k, a_k, b_k, a_m, b_n.
        run_matmul(SA_ROWS, SA_COLS, 8, 0, 0,
                   m_dim_t'(0), n_dim_t'(SA_COLS));
        compute_golden_slice(last_cmd, 1'b1);
        print_golden();
        print_dut_result();
        check_result();

        // ---------- Case 8: A third row tile; B third column tile ----------
        apply_reset();
        $display("\n===== CASE 8: A third row tile; B third column tile =====");
        // Arguments: m, n, k, a_k, b_k, a_m, b_n.
        run_matmul(SA_ROWS, SA_COLS, 8, 0, 0,
                   m_dim_t'(2 * SA_ROWS), n_dim_t'(2 * SA_COLS));
        compute_golden_slice(last_cmd, 1'b1);
        print_golden();
        print_dut_result();
        check_result();

        if (errors == 0)
            $display("\nTEST PASSED");
        else
            $fatal(1, "\nTEST FAILED: %0d mismatches", errors);
        $finish;
    end
endmodule
