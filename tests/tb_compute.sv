`timescale 1ns/1ps

import fa_pkg::*;

/*
 * ============================================================================
 *  Module: tb_compute
 * ============================================================================
 *
 *  Description:
 *      Internal compute-path verification testbench for the Flash Attention
 *      accelerator.
 *
 *      Unlike tb_uart, this testbench bypasses the external UART protocol and
 *      directly exercises fa_top. Input fixture images are loaded into the
 *      actual BRAM instances inside the DUT while independent reference copies
 *      are maintained by the testbench.
 *
 *      The test verifies:
 *
 *          1. Q, K, and V BRAM contents remain unchanged during execution.
 *
 *          2. Matrix-multiply command ordering and Q/K tile offsets.
 *
 *          3. Exact MXU score results against golden score fixtures.
 *
 *          4. V-buffer fetch address ordering and captured V tiles.
 *
 *          5. VPU row, exponential, reciprocal, and scaling request counts.
 *
 *          6. Full-width normalized VPU outputs.
 *
 *          7. Output write addresses, write counts, and output values.
 *
 *          8. Host output-memory readback behavior.
 *
 *          9. Reset/abort behavior during multiple compute pipeline stages.
 *
 *         10. Rejection of unsupported sequence lengths.
 *
 *      The DENSE parameter selects the Q/K memory layout implemented by the
 *      DUT while preserving the same functional verification sequence.
 *
 * Author: Paulo Dietrich via an agentic workflow
 * ============================================================================
 */

module tb_compute #(
    parameter bit DENSE = 0
);

    // ------------------------------------------------------------------------
    // DUT control interface
    // ------------------------------------------------------------------------

    logic clk = 0;
    logic rst_n = 0;
    logic start = 0;

    logic busy;
    logic done;
    logic error;
    logic write_done;

    logic [MAX_TILE_SQ_LEN_W-1:0] length;


    // ------------------------------------------------------------------------
    // Clock generation
    // ------------------------------------------------------------------------

    // 100 MHz simulation clock.
    always #5 clk = ~clk;


    // ------------------------------------------------------------------------
    // Internal DUT observation signals
    // ------------------------------------------------------------------------
    //
    // These signals observe the actual memory request and output-write
    // interfaces generated inside fa_top.

    logic rd_en[NUM_BUF];
    logic we   [NUM_PORTS];

    logic [BUF_ADDR_W-1:0] ra[NUM_BUF][NUM_PORTS];
    logic [BUF_ADDR_W-1:0] wa[NUM_PORTS];

    buf_word_t rd_data[NUM_BUF][NUM_PORTS];
    buf_word_t wd     [NUM_PORTS];


    // ------------------------------------------------------------------------
    // Reference fixture images
    // ------------------------------------------------------------------------
    //
    // These arrays are independent scoreboards. They do not provide DUT read
    // responses.

    buf_word_t qram[BUF_DEPTH];
    buf_word_t kram[BUF_DEPTH];
    buf_word_t vram[BUF_DEPTH];

    // Snapshot used to verify that reset does not modify output BRAM contents.
    buf_word_t reset_o_snapshot[BUF_DEPTH];


    // ------------------------------------------------------------------------
    // Output readback interface
    // ------------------------------------------------------------------------

    logic o_rd_en = 0;
    logic o_rd_valid;

    logic [BUF_ADDR_W-1:0] o_rd_addr[NUM_PORTS];

    buf_word_t o_rd_data[NUM_PORTS];


    // ------------------------------------------------------------------------
    // Golden arithmetic results
    // ------------------------------------------------------------------------

    buf_word_t expected_words[BUF_DEPTH];

    accumulator_t expected_scores[MAX_TOKENS*MAX_TOKENS];
    accumulator_t expected_norm  [MAX_TOKENS*D_MODEL];


    // ------------------------------------------------------------------------
    // Fixture configuration
    // ------------------------------------------------------------------------

    string root_dir;
    string folder;

    int jobs;
    int n;
    int job_fd;
    int ignored;


    // ------------------------------------------------------------------------
    // Device under test
    // ------------------------------------------------------------------------

    fa_top #(
        .QK_DENSE_LAYOUT(DENSE)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),

        .start       (start),
        .tile_sq_len (length),

        .busy        (busy),
        .done        (done),
        .config_error(error),

        // Host memory interface is unused by this testbench.
        .host_req      (1'b0),
        .host_we       (1'b0),
        .host_bank     (2'b0),
        .host_addr     ('0),
        .host_wdata    ('0),
        .host_ready    (),
        .host_rsp_valid(),
        .host_rdata    (),

        // Output BRAM readback interface.
        .o_rd_en     (o_rd_en),
        .o_rd_addr   (o_rd_addr),
        .o_rd_data   (o_rd_data),
        .o_rd_valid  (o_rd_valid),

        .o_write_done(write_done)
    );


    // ------------------------------------------------------------------------
    // Internal DUT observation
    // ------------------------------------------------------------------------
    //
    // Storage and all registered BRAM responses belong to the real BRAM
    // instances inside fa_top. These aliases only expose internal activity
    // to the verification scoreboards.

    assign rd_en   = dut.rd_en;
    assign ra      = dut.rd_addr;
    assign rd_data = dut.rd_data;

    assign wa = dut.o_wr_addr;
    assign we = dut.o_we;
    assign wd = dut.embd_out;


    // ------------------------------------------------------------------------
    // Fixture loading
    // ------------------------------------------------------------------------
    //
    // Loads one complete job into both the independent reference arrays and
    // the actual BRAM instances used by the DUT.

    task automatic load_job(
        input int job
    );
        folder = $sformatf("%s/%03d", root_dir, job);


        // --------------------------------------------------------------------
        // Read sequence length
        // --------------------------------------------------------------------

        job_fd = $fopen({folder, "/n.txt"}, "r");

        assert (job_fd != 0)
            else $fatal(1, "Missing fixture %s", folder);

        ignored = $fscanf(job_fd, "%d", n);

        $fclose(job_fd);


        // --------------------------------------------------------------------
        // Load independent reference input images
        // --------------------------------------------------------------------

        $readmemh({folder, "/q.hex"}, qram);
        $readmemh({folder, "/k.hex"}, kram);
        $readmemh({folder, "/v.hex"}, vram);


        // --------------------------------------------------------------------
        // Load actual DUT input BRAMs
        // --------------------------------------------------------------------

        $readmemh(
            {folder, "/q.hex"},
            dut.U_SRAM.g_buf[0].U_BRAM.mem
        );

        $readmemh(
            {folder, "/k.hex"},
            dut.U_SRAM.g_buf[1].U_BRAM.mem
        );

        $readmemh(
            {folder, "/v.hex"},
            dut.U_SRAM.g_buf[2].U_BRAM.mem
        );


        // --------------------------------------------------------------------
        // Load golden intermediate and final results
        // --------------------------------------------------------------------

        $readmemh(
            {folder, "/scores.hex"},
            expected_scores,
            0,
            n*n-1
        );

        $readmemh(
            {folder, "/out.hex"},
            expected_words,
            0,
            n*4-1
        );

        $readmemh(
            {folder, "/norm.hex"},
            expected_norm,
            0,
            n*16-1
        );


        // --------------------------------------------------------------------
        // Initialize output BRAM with a sentinel value
        // ------------------------------------------------------------------------
        //
        // Any write outside the expected output range can therefore be
        // detected during readback.

        for (int a = 0; a < BUF_DEPTH; a++) begin
            dut.U_SRAM.g_buf[3].U_BRAM.mem[a] = 32'hDEADBEEF;
        end
    endtask


    // ------------------------------------------------------------------------
    // Input-memory integrity check
    // ------------------------------------------------------------------------
    //
    // Q, K, and V memories are read-only during normal accelerator execution.
    // Every location must therefore still match its original fixture image.

    task automatic check_input_memories;
        for (int a = 0; a < BUF_DEPTH; a++) begin

            assert (
                dut.U_SRAM.g_buf[0].U_BRAM.mem[a] === qram[a]
            ) else $fatal(1, "Q memory changed");

            assert (
                dut.U_SRAM.g_buf[1].U_BRAM.mem[a] === kram[a]
            ) else $fatal(1, "K memory changed");

            assert (
                dut.U_SRAM.g_buf[2].U_BRAM.mem[a] === vram[a]
            ) else $fatal(1, "V memory changed");
        end
    endtask


    // ------------------------------------------------------------------------
    // Output-memory readback verification
    // ------------------------------------------------------------------------
    //
    // Exercises the official fa_top output readback interface rather than
    // inspecting O BRAM contents directly.

    task automatic readback_output;

        // Readback starts at a falling edge. Addresses are stable before the
        // following rising edge, and the corresponding registered data and
        // valid signal must be visible by the next falling edge.
        o_rd_en = 1;

        for (int a = 0; a < BUF_DEPTH; a += NUM_PORTS) begin

            // Present one address per output-memory port.
            for (int p = 0; p < NUM_PORTS; p++) begin
                o_rd_addr[p] = BUF_ADDR_W'(a+p);
            end

            @(negedge clk);

            assert (o_rd_valid)
                else $fatal(1, "Missing O readback response");

            for (int p = 0; p < NUM_PORTS; p++) begin

                // Valid output region must exactly match the golden fixture.
                if (a+p < n*4) begin
                    assert (
                        o_rd_data[p] === expected_words[a+p]
                    ) else begin
                        $fatal(
                            1,
                            "O readback mismatch addr=%0d",
                            a+p
                        );
                    end
                end

                // Locations beyond the expected output must retain the
                // sentinel value, proving that no out-of-range write occurred.
                else begin
                    assert (
                        o_rd_data[p] === 32'hDEADBEEF
                    ) else begin
                        $fatal(
                            1,
                            "Out-of-range O write addr=%0d",
                            a+p
                        );
                    end
                end
            end
        end


        // --------------------------------------------------------------------
        // Disable readback and verify valid clears
        // --------------------------------------------------------------------

        o_rd_en = 0;

        @(negedge clk);

        assert (!o_rd_valid)
            else $fatal(
                1,
                "O readback valid did not clear"
            );


        // Computation and readback must not modify Q, K, or V.
        check_input_memories();
    endtask


    // ------------------------------------------------------------------------
    // Execute and verify one loaded job
    // ------------------------------------------------------------------------

    task automatic run_loaded(
        input int job
    );
        int cycles;

        int commands;
        int words;
        int blocks;

        int fetch_beats;
        int fetches;

        int rows;
        int exps;
        int rcps;
        int scls;

        int q_base;
        int k_base;
        int address;


        // --------------------------------------------------------------------
        // Initialize scoreboard counters
        // --------------------------------------------------------------------

        commands    = 0;
        words       = 0;
        blocks      = 0;

        fetch_beats = 0;
        fetches     = 0;

        rows        = 0;
        exps        = 0;
        rcps        = 0;
        scls        = 0;

        cycles      = 0;


        // --------------------------------------------------------------------
        // Start computation
        // --------------------------------------------------------------------

        length = MAX_TILE_SQ_LEN_W'(n);
        start  = 1;

        // Attempt output readback during start/computation. The DUT must
        // suppress these requests while the accelerator owns the memories.
        o_rd_en = 1;

        @(negedge clk);

        start  = 0;

        // Deliberately change the external input after START to verify that the
        // accepted configuration has been internally latched by the DUT.
        length = 8;


        // --------------------------------------------------------------------
        // Monitor compute pipeline
        // --------------------------------------------------------------------

        while (!done && cycles < 6000000) begin

            // ---------------------------------------------------------------
            // Readback arbitration
            // ---------------------------------------------------------------

            assert (
                !error       &&
                !rd_en[3]    &&
                !o_rd_valid
            ) else begin
                $fatal(
                    1,
                    "Readback accepted while computing"
                );
            end


            // ---------------------------------------------------------------
            // MXU command ordering
            // ---------------------------------------------------------------

            q_base = int'(dut.mxu_cmd.a_m_offset);
            k_base = int'(dut.mxu_cmd.b_n_offset);

            if (dut.mxu_start) begin

                // Expected traversal:
                //
                //      q_base advances by 8 after all K/V tiles for the
                //      current Q tile have been processed.
                //
                //      k_base advances by 8 for each command within a Q tile.
                assert (
                    q_base == commands/(n/8)*8 &&
                    k_base == commands%(n/8)*8
                ) else begin
                    $fatal(
                        1,
                        "Command order"
                    );
                end

                commands++;
            end


            // ---------------------------------------------------------------
            // MXU score verification
            // ---------------------------------------------------------------

            if (dut.mxu_done) begin
                for (int r = 0; r < 8; r++) begin
                    for (int c = 0; c < 8; c++) begin

                        assert (
                            dut.scores[r][c] ==
                            expected_scores[
                                (q_base+r)*n + k_base+c
                            ]
                        ) else begin
                            $fatal(
                                1,
                                "Q/K or GEMM mismatch job=%0d q=%0d k=%0d r=%0d c=%0d got=%0d expected=%0d",
                                job,
                                q_base,
                                k_base,
                                r,
                                c,
                                dut.scores[r][c],
                                expected_scores[
                                    (q_base+r)*n + k_base+c
                                ]
                            );
                        end
                    end
                end
            end


            // ---------------------------------------------------------------
            // V-buffer fetch address ordering
            // ---------------------------------------------------------------

            if (rd_en[2]) begin
                for (int p = 0; p < 2; p++) begin
                    assert (
                        int'(ra[2][p]) ==
                        k_base*4 + (fetch_beats%16)*2 + p
                    ) else begin
                        $fatal(
                            1,
                            "V address order"
                        );
                    end
                end

                fetch_beats++;
            end


            // ---------------------------------------------------------------
            // V-tile capture verification
            // ---------------------------------------------------------------

            if (dut.U_VPU.U_VF.vf_done) begin
                fetches++;

                for (int r = 0; r < 8; r++) begin
                    for (int d = 0; d < 16; d++) begin

                        address = (k_base+r)*4 + d/4;

                        assert (
                            dut.U_VPU.v_tile[r][d] ==
                            operand_t'(
                                vram[address][31-(d%4)*8 -: 8]
                            )
                        ) else begin
                            $fatal(
                                1,
                                "V capture mismatch job=%0d row=%0d dim=%0d",
                                job,
                                r,
                                d
                            );
                        end
                    end
                end
            end


            // ---------------------------------------------------------------
            // VPU primitive request accounting
            // ---------------------------------------------------------------

            if (dut.U_VPU.vpu_row_start)
                rows++;

            if (dut.U_VPU.U_VROW.exp_start)
                exps++;

            if (dut.U_VPU.U_VROW.rcp_start)
                rcps++;

            if (dut.U_VPU.U_VROW.scl_start)
                scls++;


            // ---------------------------------------------------------------
            // Full-width normalized output verification
            // ---------------------------------------------------------------

            if (dut.vpu_done && dut.last_kv) begin

                for (int r = 0; r < 8; r++) begin
                    for (int d = 0; d < 16; d++) begin

                        assert (
                            dut.U_VPU.o_norm[r][d] ==
                            expected_norm[
                                (q_base+r)*16 + d
                            ]
                        ) else begin
                            $fatal(
                                1,
                                "Full-width normalization mismatch job=%0d row=%0d dim=%0d got=%0d expected=%0d",
                                job,
                                q_base+r,
                                d,
                                dut.U_VPU.o_norm[r][d],
                                expected_norm[
                                    (q_base+r)*16 + d
                                ]
                            );
                        end
                    end
                end
            end


            // ---------------------------------------------------------------
            // Output write verification
            // ---------------------------------------------------------------

            for (int p = 0; p < 2; p++) begin
                if (we[p]) begin

                    assert (
                        busy             &&
                        dut.last_kv      &&
                        int'(wa[p]) == words &&
                        words < n*4
                    ) else begin
                        $fatal(
                            1,
                            "Write address/count"
                        );
                    end

                    assert (
                        wd[p] == expected_words[words]
                    ) else begin
                        $fatal(
                            1,
                            "Output mismatch job=%0d addr=%0d got=%08x expected=%08x",
                            job,
                            words,
                            wd[p],
                            expected_words[words]
                        );
                    end

                    words++;
                end
            end


            // One write_done pulse is expected for each completed Q block.
            if (write_done)
                blocks++;


            // Advance simulation.
            cycles++;

            @(negedge clk);
        end


        // --------------------------------------------------------------------
        // Completion checks
        // --------------------------------------------------------------------

        assert (
            done   &&
            !busy  &&
            !we[0] &&
            !we[1]
        ) else begin
            $fatal(
                1,
                "Completion timeout"
            );
        end


        // Number of 8x8 Q/K tile operations.
        assert (
            commands == (n/8)*(n/8) &&
            words    == n*4         &&
            blocks   == n/8
        ) else begin
            $fatal(
                1,
                "Operation counts"
            );
        end


        // Every MXU command requires one V tile consisting of sixteen
        // two-word BRAM fetch beats, followed by eight VPU rows.
        assert (
            fetches     == commands    &&
            fetch_beats == commands*16 &&
            rows        == commands*8
        ) else begin
            $fatal(
                1,
                "Fetch/row count"
            );
        end


        // Each VPU row performs:
        //
        //      16 exponential requests
        //       1 reciprocal request
        //      17 scaling requests
        assert (
            exps == rows*16 &&
            rcps == rows    &&
            scls == rows*17
        ) else begin
            $fatal(
                1,
                "Duplicate or lost primitive requests"
            );
        end


        // Verify final BRAM contents through the external readback interface.
        readback_output();


        // --------------------------------------------------------------------
        // Report successful job
        // --------------------------------------------------------------------

        $display(
            "PASS job=%0d N=%0d dense=%0b frac=%0d commands=%0d fetch_beats=%0d O_words=%0d cycles=%0d",
            job,
            n,
            DENSE,
            FRAC_BITS,
            commands,
            fetch_beats,
            words,
            cycles
        );


        // DONE must be a one-cycle pulse.
        @(negedge clk);

        assert (!done)
            else $fatal(
                1,
                "Done not a pulse"
            );
    endtask


    // ------------------------------------------------------------------------
    // Main test sequence
    // ------------------------------------------------------------------------

    initial begin

        // Fixture root directory and number of jobs are supplied by the
        // simulation command line.
        assert ($value$plusargs("ROOT=%s", root_dir))
            else $fatal;

        assert ($value$plusargs("JOBS=%d", jobs))
            else $fatal;


        // --------------------------------------------------------------------
        // Initial reset
        // --------------------------------------------------------------------

        length    = 0;
        o_rd_addr = '{default:'0};

        repeat (2) @(negedge clk);

        rst_n = 1;


        // --------------------------------------------------------------------
        // Run all supplied fixture jobs
        // --------------------------------------------------------------------

        for (int job = 0; job < jobs; job++) begin
            load_job(job);
            run_loaded(job);
        end


        // --------------------------------------------------------------------
        // Reset / abort verification
        // ------------------------------------------------------------------------
        //
        // Reset is asserted during three different pipeline stages:
        //
        //      stage 0 : V-buffer read streaming
        //      stage 1 : VPU scaling arithmetic
        //      stage 2 : output BRAM writeback
        //
        // Each abort must leave the accelerator idle without corrupting the
        // input or output memories. The same fixture is then restarted to
        // verify clean recovery.

        for (int stage = 0; stage < 3; stage++) begin
            int timeout_cycles;


            // ---------------------------------------------------------------
            // Start fixture
            // ---------------------------------------------------------------

            load_job(0);

            length = 8;
            start  = 1;

            @(negedge clk);

            start = 0;

            timeout_cycles = 0;


            // ---------------------------------------------------------------
            // Wait until selected pipeline stage becomes active
            // ---------------------------------------------------------------

            while (
                !(
                    (stage == 0 && rd_en[2])                    ||
                    (stage == 1 && dut.U_VPU.U_VROW.scl_busy)  ||
                    (stage == 2 && we[0])
                )
            ) begin
                @(negedge clk);

                timeout_cycles++;

                assert (timeout_cycles < 10000)
                    else $fatal(
                        1,
                        "Abort stage not reached"
                    );
            end


            // ---------------------------------------------------------------
            // Assert reset
            // ---------------------------------------------------------------

            rst_n = 0;


            // Snapshot output memory immediately before reset processing.
            for (int a = 0; a < BUF_DEPTH; a++) begin
                reset_o_snapshot[a] =
                    dut.U_SRAM.g_buf[3].U_BRAM.mem[a];
            end

            repeat (2) @(negedge clk);


            // ---------------------------------------------------------------
            // Verify reset clears control activity
            // ---------------------------------------------------------------

            assert (
                !busy       &&
                !done       &&
                !we[0]      &&
                !we[1]      &&
                !rd_en[2]   &&
                !o_rd_valid
            ) else begin
                $fatal(
                    1,
                    "Reset failed"
                );
            end


            // Input BRAMs must survive reset unchanged.
            check_input_memories();


            // Output BRAM must also retain whatever contents existed at the
            // instant reset was asserted.
            for (int a = 0; a < BUF_DEPTH; a++) begin
                assert (
                    dut.U_SRAM.g_buf[3].U_BRAM.mem[a] ===
                    reset_o_snapshot[a]
                ) else begin
                    $fatal(
                        1,
                        "Reset changed O memory"
                    );
                end
            end


            // ---------------------------------------------------------------
            // Release reset
            // ---------------------------------------------------------------

            rst_n = 1;

            // Ensure no stale pipeline state produces a delayed completion or
            // output write after reset release.
            repeat (4) begin
                @(negedge clk);

                assert (
                    !done  &&
                    !we[0] &&
                    !we[1]
                ) else begin
                    $fatal(
                        1,
                        "Ghost completion"
                    );
                end
            end


            // ---------------------------------------------------------------
            // Reload and rerun after abort
            // ---------------------------------------------------------------

            load_job(0);

            run_loaded(100 + stage);

            $display(
                "PASS abort/restart stage=%0d",
                stage
            );
        end


        // --------------------------------------------------------------------
        // Invalid configuration rejection
        // ------------------------------------------------------------------------
        //
        // Unsupported inputs must produce config_error immediately rather than
        // entering the compute pipeline, deadlocking, or silently processing a
        // partial tail.

        for (int invalid = 0; invalid < 4; invalid++) begin

            case (invalid)
                0: length = 0;
                1: length = 7;
                2: length = 9;
                3: length = 264;
            endcase

            start = 1;

            #1;

            assert (
                error &&
                !busy
            ) else $fatal;

            @(negedge clk);

            start = 0;


            // Rejected requests must not start later.
            repeat (4) begin
                @(negedge clk);

                assert (
                    !busy &&
                    !done
                ) else $fatal;
            end
        end


        // --------------------------------------------------------------------
        // Test complete
        // --------------------------------------------------------------------

        $display(
            "PASS all INTERNAL BRAM, O readback, arithmetic, reset and rejection scoreboards"
        );

        $finish;
    end

endmodule