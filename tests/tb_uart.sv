`timescale 1ns/1ps

/*
 * ============================================================================
 *  Module: tb_uart
 * ============================================================================
 *
 *  Description:
 *      End-to-end UART testbench for the Flash Attention accelerator.
 *
 *      All accelerator configuration, memory loading, execution control, and
 *      output readback are performed exclusively through the UART pins. The
 *      testbench therefore verifies the complete external communication path
 *      rather than accessing accelerator memories directly.
 *
 *      The test performs the following operations:
 *
 *          1. Load Q, K, and V fixture images from disk.
 *
 *          2. Issue a STATUS command and verify the protocol response.
 *
 *          3. Issue a RESET command.
 *
 *          4. Write Q, K, and V into the accelerator through UART WRITE
 *             commands.
 *
 *          5. Read each input buffer back through UART READ commands and
 *             verify exact data integrity.
 *
 *          6. Start the accelerator using the requested sequence length.
 *
 *          7. Poll STATUS until computation completes.
 *
 *          8. Read the output buffer through UART and compare every output
 *             word against the golden fixture.
 *
 *      UART packets use the same stop-and-wait command protocol implemented
 *      by uart_command:
 *
 *          Request:
 *              A5 5A seq cmd len_hi len_lo payload CRC16_hi CRC16_lo
 *
 *          Response:
 *              5A A5 seq status len_hi len_lo payload CRC16_hi CRC16_lo
 *
 *      CRC:
 *          CRC-16/CCITT-FALSE
 *          Polynomial : 0x1021
 *          Initial    : 0xFFFF
 *
 * Author: Paulo Dietrich via an agentic workflow
 * ============================================================================
 */

module tb_uart;

    // ------------------------------------------------------------------------
    // Testbench configuration
    // ------------------------------------------------------------------------

    // UART clocks per bit.
    //
    // DUT configuration:
    //      CLK_HZ = 800 kHz
    //      BAUD   = 100 kbaud
    //
    // Therefore:
    //      CPB = 800000 / 100000 = 8 clocks/bit
    localparam int CPB = 8;


    // ------------------------------------------------------------------------
    // DUT interface signals
    // ------------------------------------------------------------------------

    logic clk = 0;
    logic rst_n = 0;

    logic rx = 1;
    logic tx;

    logic busy;
    logic done_latched;
    logic error_latched;


    // ------------------------------------------------------------------------
    // Clock generation
    // ------------------------------------------------------------------------

    // 100 MHz simulation clock.
    always #5 clk = ~clk;


    // ------------------------------------------------------------------------
    // Device under test
    // ------------------------------------------------------------------------

    fa_uart_top #(
        .CLK_HZ           (800000),
        .BAUD             (100000),
        .RX_TIMEOUT_CYCLES(4096)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .uart_rx_pin  (rx),
        .uart_tx_pin  (tx),
        .busy         (busy),
        .done_latched (done_latched),
        .error_latched(error_latched)
    );


    // ------------------------------------------------------------------------
    // UART response storage
    // ------------------------------------------------------------------------

    // Bytes decoded from the DUT TX pin are placed into this queue.
    byte unsigned incoming[$];

    // Maximum WRITE request:
    //
    //      5-byte memory header
    //      64 words * 4 bytes/word
    //
    //      Total = 261 bytes
    byte unsigned request_data [0:260];

    // Maximum READ response:
    //
    //      64 words * 4 bytes/word = 256 bytes
    byte unsigned response_data[0:255];

    byte unsigned sequence_id = 0;


    // ------------------------------------------------------------------------
    // Fixture storage
    // ------------------------------------------------------------------------

    logic [31:0] q_image [0:1023];
    logic [31:0] k_image [0:1023];
    logic [31:0] v_image [0:1023];
    logic [31:0] expected[0:1023];

    string root_dir;
    string folder;

    int case_id;
    int n;
    int fd;
    int ignored;
    int response_size;


    // ------------------------------------------------------------------------
    // CRC-16/CCITT-FALSE
    // ------------------------------------------------------------------------
    //
    // Processes one byte and returns the updated CRC value.

    function automatic logic [15:0] crc_byte(
        input logic [15:0] crc,
        input logic [7:0]  b
    );
        logic [15:0] value;

        // XOR the next byte into the upper half of the CRC register.
        value = crc ^ {b, 8'b0};

        // Process each bit using polynomial 0x1021.
        for (int i = 0; i < 8; i++) begin
            value = value[15]
                ? (value << 1) ^ 16'h1021
                : (value << 1);
        end

        return value;
    endfunction


    // ------------------------------------------------------------------------
    // Fixture data helper
    // ------------------------------------------------------------------------
    //
    // Returns one source word from the selected Q, K, or V fixture image.

    function automatic logic [31:0] source_word(
        input int bank,
        input int address
    );
        case (bank)
            0:       return q_image[address];
            1:       return k_image[address];
            default: return v_image[address];
        endcase
    endfunction


    // ------------------------------------------------------------------------
    // UART transmit decoder
    // ------------------------------------------------------------------------
    //
    // Independently decodes bytes transmitted by the DUT.
    //
    // Sampling occurs at the center of each data bit rather than using any
    // internal UART state from the DUT.

    initial forever begin
        byte unsigned value;

        // Detect falling edge of the UART start bit.
        @(negedge tx);

        // Move to the center of data bit 0:
        //
        //      1 start bit + 1/2 bit
        #(CPB*10 + CPB*5);

        // Receive eight LSB-first data bits.
        for (int i = 0; i < 8; i++) begin
            value[i] = tx;
            #(CPB*10);
        end

        // UART frame must terminate with a high stop bit.
        assert (tx === 1'b1)
            else $fatal(1, "TX stop-bit error");

        incoming.push_back(value);
    end


    // ------------------------------------------------------------------------
    // UART byte transmitter
    // ------------------------------------------------------------------------
    //
    // Sends one 8-N-1 UART byte to the DUT RX pin.

    task automatic send_byte(
        input byte unsigned value
    );
        // Start bit.
        @(negedge clk);
        rx = 0;
        repeat (CPB) @(negedge clk);

        // Eight LSB-first data bits.
        for (int i = 0; i < 8; i++) begin
            rx = value[i];
            repeat (CPB) @(negedge clk);
        end

        // Stop bit.
        rx = 1;
        repeat (CPB) @(negedge clk);
    endtask


    // ------------------------------------------------------------------------
    // UART byte receiver
    // ------------------------------------------------------------------------
    //
    // Waits for one byte decoded from the DUT TX pin.

    task automatic receive_byte(
        output byte unsigned value
    );
        int timeout_count;

        timeout_count = 0;

        while (incoming.size() == 0) begin
            @(negedge clk);
            timeout_count++;

            assert (timeout_count < 20000)
                else $fatal(1, "UART response timeout");
        end

        value = incoming.pop_front();
    endtask


    // ------------------------------------------------------------------------
    // UART command transaction
    // ------------------------------------------------------------------------
    //
    // Builds and sends one complete request packet, receives the corresponding
    // response packet, and verifies synchronization, sequence ID, status,
    // payload length, and CRC.

    task automatic transaction(
        input byte unsigned command,
        input int           length,
        input byte unsigned wanted_status = 0
    );
        logic [15:0] crc;
        logic [15:0] received_crc;

        byte unsigned b;
        byte unsigned header[0:3];

        // --------------------------------------------------------------------
        // Transmit request
        // --------------------------------------------------------------------

        crc = 16'hFFFF;

        // Synchronization bytes are not included in the CRC.
        send_byte(8'hA5);
        send_byte(8'h5A);

        // Sequence ID.
        send_byte(sequence_id);
        crc = crc_byte(crc, sequence_id);

        // Command opcode.
        send_byte(command);
        crc = crc_byte(crc, command);

        // Payload length, big-endian.
        b = 8'(length >> 8);
        send_byte(b);
        crc = crc_byte(crc, b);

        b = 8'(length);
        send_byte(b);
        crc = crc_byte(crc, b);

        // Payload.
        for (int i = 0; i < length; i++) begin
            send_byte(request_data[i]);
            crc = crc_byte(crc, request_data[i]);
        end

        // CRC, big-endian.
        send_byte(crc[15:8]);
        send_byte(crc[7:0]);


        // --------------------------------------------------------------------
        // Receive response
        // --------------------------------------------------------------------

        receive_byte(b);
        assert (b == 8'h5A)
            else $fatal(1, "Response magic A");

        receive_byte(b);
        assert (b == 8'hA5)
            else $fatal(1, "Response magic B");


        // --------------------------------------------------------------------
        // Verify response header
        // --------------------------------------------------------------------

        crc = 16'hFFFF;

        // Header contains:
        //
        //      sequence
        //      status
        //      length high
        //      length low
        for (int i = 0; i < 4; i++) begin
            receive_byte(header[i]);
            crc = crc_byte(crc, header[i]);
        end

        assert (
            header[0] == sequence_id &&
            header[1] == wanted_status
        ) else begin
            $fatal(
                1,
                "Response seq/status got=%0d",
                header[1]
            );
        end

        response_size = int'({header[2], header[3]});

        assert (response_size <= 256)
            else $fatal(1, "Response length");


        // --------------------------------------------------------------------
        // Receive response payload
        // --------------------------------------------------------------------

        for (int i = 0; i < response_size; i++) begin
            receive_byte(response_data[i]);
            crc = crc_byte(crc, response_data[i]);
        end


        // --------------------------------------------------------------------
        // Verify response CRC
        // --------------------------------------------------------------------

        receive_byte(b);
        received_crc[15:8] = b;

        receive_byte(b);
        received_crc[7:0] = b;

        assert (received_crc == crc)
            else $fatal(1, "Response CRC");

        // Advance protocol sequence number after a complete transaction.
        sequence_id = sequence_id + 1'b1;
    endtask


    // ------------------------------------------------------------------------
    // Memory command helper
    // ------------------------------------------------------------------------
    //
    // Constructs the common five-byte header used by READ and WRITE commands:
    //
    //      Byte 0   : bank
    //      Byte 1-2 : base address
    //      Byte 3-4 : number of words

    task automatic memory_header(
        input int bank,
        input int address,
        input int count
    );
        request_data[0] = 8'(bank);

        request_data[1] = 8'(address >> 8);
        request_data[2] = 8'(address);

        request_data[3] = 8'(count >> 8);
        request_data[4] = 8'(count);
    endtask


    // ------------------------------------------------------------------------
    // Main test sequence
    // ------------------------------------------------------------------------

    initial begin
        int count;
        int polls;

        logic [31:0] value;


        // --------------------------------------------------------------------
        // Load fixture configuration
        // --------------------------------------------------------------------

        assert ($value$plusargs("ROOT=%s", root_dir))
            else $fatal(
                1,
                "Supply +ROOT=fixtures/dummy_fixed"
            );

        case_id = 0;
        ignored = $value$plusargs("CASE=%d", case_id);

        folder = $sformatf("%s/%03d", root_dir, case_id);


        // Read sequence length.
        fd = $fopen({folder, "/n.txt"}, "r");

        assert (fd != 0)
            else $fatal(1, "Missing fixture %s", folder);

        ignored = $fscanf(fd, "%d", n);
        $fclose(fd);


        // Load Q, K, V, and expected output images.
        $readmemh({folder, "/q.hex"},   q_image);
        $readmemh({folder, "/k.hex"},   k_image);
        $readmemh({folder, "/v.hex"},   v_image);
        $readmemh(
            {folder, "/out.hex"},
            expected,
            0,
            n*4-1
        );


        // --------------------------------------------------------------------
        // Release reset
        // --------------------------------------------------------------------

        repeat (5) @(negedge clk);
        rst_n = 1;


        // --------------------------------------------------------------------
        // Verify STATUS command
        // --------------------------------------------------------------------

        transaction(4, 0);

        assert (
            response_size    == 22 &&
            response_data[0] == 8'h46
        ) else $fatal;


        // --------------------------------------------------------------------
        // Reset accelerator core
        // --------------------------------------------------------------------

        transaction(5, 0);


        // --------------------------------------------------------------------
        // Load and verify Q, K, and V buffers
        // --------------------------------------------------------------------
        //
        // Each buffer contains 1024 words. Transfers occur in blocks of
        // 64 words, which is the maximum command size supported by the UART
        // protocol.

        for (int bank = 0; bank < 3; bank++) begin
            for (int address = 0; address < 1024; address += 64) begin

                // ------------------------------------------------------------
                // Write 64 words
                // ------------------------------------------------------------

                memory_header(bank, address, 64);

                for (int w = 0; w < 64; w++) begin
                    value = source_word(bank, address + w);

                    // Serialize each word in big-endian byte order.
                    for (int b = 0; b < 4; b++) begin
                        request_data[5 + w*4 + b] =
                            value[31-b*8 -: 8];
                    end
                end

                transaction(1, 261);


                // ------------------------------------------------------------
                // Read the same 64 words back
                // ------------------------------------------------------------

                memory_header(bank, address, 64);
                transaction(2, 5);

                assert (response_size == 256)
                    else $fatal;


                // ------------------------------------------------------------
                // Verify exact input-buffer contents
                // ------------------------------------------------------------

                for (int w = 0; w < 64; w++) begin
                    value = {
                        response_data[w*4],
                        response_data[w*4+1],
                        response_data[w*4+2],
                        response_data[w*4+3]
                    };

                    assert (
                        value === source_word(bank, address+w)
                    ) else begin
                        $fatal(
                            1,
                            "Input readback bank=%0d addr=%0d",
                            bank,
                            address+w
                        );
                    end
                end
            end

            $display(
                "PASS UART load and readback bank=%0d",
                bank
            );
        end


        // --------------------------------------------------------------------
        // Start accelerator
        // --------------------------------------------------------------------

        // START payload contains the sequence length as two big-endian bytes.
        request_data[0] = 8'(n >> 8);
        request_data[1] = 8'(n);

        transaction(3, 2);


        // --------------------------------------------------------------------
        // Poll accelerator status
        // ------------------------------------------------------------------------
        //
        // response_data[3]:
        //
        //      bit 0 = busy
        //      bit 1 = done_latched
        //      bit 2 = error_latched

        polls = 0;

        do begin
            transaction(4, 0);

            polls++;

            assert (polls < 20000)
                else $fatal(1, "Compute timeout");

        end while (
            !response_data[3][1] ||
             response_data[3][0]
        );


        // --------------------------------------------------------------------
        // Read and verify output buffer
        // ------------------------------------------------------------------------

        for (int address = 0; address < n*4; address += 64) begin

            // Final block may contain fewer than 64 words.
            count = (n*4-address < 64)
                ? n*4-address
                : 64;

            memory_header(3, address, count);
            transaction(2, 5);

            for (int w = 0; w < count; w++) begin
                value = {
                    response_data[w*4],
                    response_data[w*4+1],
                    response_data[w*4+2],
                    response_data[w*4+3]
                };

                assert (
                    value === expected[address+w]
                ) else begin
                    $fatal(
                        1,
                        "O mismatch word=%0d got=%08x expected=%08x",
                        address+w,
                        value,
                        expected[address+w]
                    );
                end
            end
        end


        // --------------------------------------------------------------------
        // Test complete
        // --------------------------------------------------------------------

        $display(
            "PASS UART end-to-end: N=%0d, actual MXU, internal BRAM, exact O match",
            n
        );

        $finish;
    end


    // ------------------------------------------------------------------------
    // Global simulation timeout
    // ------------------------------------------------------------------------
    //
    // Prevents protocol failures from leaving the simulation running forever.

    initial begin
        #1000000000;
        $fatal(1, "Global UART test timeout");
    end

endmodule