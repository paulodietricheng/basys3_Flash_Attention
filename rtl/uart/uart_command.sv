`timescale 1ns/1ps

import fa_pkg::*;

/*
 * ============================================================================
 *  Module: uart_command
 * ============================================================================
 *
 *  Description:
 *      UART command processor used to communicate between the host PC and the
 *      Flash Attention accelerator.
 *
 *      The module receives framed command packets from the UART RX path,
 *      validates the packet length and CRC, executes the requested operation,
 *      and sends a framed response back through UART TX.
 *
 *      Supported operations:
 *
 *          0x01 - WRITE
 *                 Write one or more 32-bit words into an accelerator buffer.
 *
 *          0x02 - READ
 *                 Read one or more 32-bit words from an accelerator buffer.
 *
 *          0x03 - START
 *                 Start the accelerator using the requested sequence length.
 *
 *          0x04 - STATUS
 *                 Return accelerator status, configuration information,
 *                 clock frequency, and measured busy cycles.
 *
 *          0x05 - RESET
 *                 Reset the compute core while preserving UART communication
 *                 and buffer contents.
 *
 *  Protocol:
 *
 *      Request:
 *          A5 5A seq cmd len_hi len_lo payload CRC16_hi CRC16_lo
 *
 *      Response:
 *          5A A5 seq status len_hi len_lo payload CRC16_hi CRC16_lo
 *
 *      CRC:
 *          CRC-16/CCITT-FALSE
 *          Polynomial : 0x1021
 *          Initial    : 0xFFFF
 *
 *          The CRC covers the packet beginning at the sequence byte and ending
 *          at the final payload byte. Synchronization bytes are not included.
 *
 *  Operation:
 *
 *      1. Wait for the synchronization sequence A5 5A.
 *
 *      2. Receive the sequence number, command, payload length, payload,
 *         and CRC.
 *
 *      3. Validate the packet CRC and command arguments.
 *
 *      4. Execute the requested operation through the host memory interface
 *         or accelerator control signals.
 *
 *      5. Construct a response packet containing a status code and optional
 *         payload.
 *
 *      6. Calculate the response CRC while transmitting the packet.
 *
 *      The protocol is stop-and-wait: only one request is processed at a time.
 *      A complete request is CRC checked before any memory write occurs.
 *
 * Author: Paulo Dietrich via an agentic workflow
 * ============================================================================
 */

module uart_command #(
    parameter int CLK_HZ            = 100_000_000,
    parameter int RX_TIMEOUT_CYCLES = CLK_HZ / 10
) (
    input  logic clk,
    input  logic rst_n,

    // UART receive interface
    input  logic [7:0] rx_data,
    input  logic       rx_valid,
    input  logic       rx_error,

    // UART transmit interface
    output logic [7:0] tx_data,
    output logic       tx_valid,
    input  logic       tx_ready,

    // Accelerator control interface
    output logic                         core_rst_n,
    output logic                         start,
    output logic [MAX_TILE_SQ_LEN_W-1:0] tile_sq_len,

    input  logic busy,
    input  logic done,
    input  logic config_error,

    // Latched status outputs used by the Basys3 top level
    output logic done_latched,
    output logic error_latched,

    // Host-side buffer interface
    output logic                       host_req,
    output logic                       host_we,
    output logic      [1:0]            host_bank,
    output logic      [BUF_ADDR_W-1:0] host_addr,
    output buf_word_t                  host_wdata,

    input  logic      host_ready,
    input  logic      host_rsp_valid,
    input  buf_word_t host_rdata
);

    // ------------------------------------------------------------------------
    // Protocol constants
    // ------------------------------------------------------------------------

    // Maximum number of 32-bit words that may be transferred in one command.
    localparam int MAX_WORDS = 64;

    // WRITE requests contain:
    //      1 byte bank
    //      2 bytes address
    //      2 bytes word count
    //      4 bytes per data word
    localparam int MAX_PAYLOAD = 5 + 4 * MAX_WORDS;

    // Width of the receive timeout counter.
    localparam int TW = (RX_TIMEOUT_CYCLES < 2)
                      ? 1
                      : $clog2(RX_TIMEOUT_CYCLES);


    // ------------------------------------------------------------------------
    // Response status codes
    // ------------------------------------------------------------------------

    localparam logic [7:0] OK           = 0;
    localparam logic [7:0] BAD_CRC      = 1;
    localparam logic [7:0] BAD_COMMAND  = 2;
    localparam logic [7:0] BAD_ARGUMENT = 3;
    localparam logic [7:0] IS_BUSY      = 4;
    localparam logic [7:0] RX_TIMEOUT   = 5;
    localparam logic [7:0] BAD_FRAME    = 6;
    localparam logic [7:0] BAD_LENGTH   = 7;


    // ------------------------------------------------------------------------
    // Command processor state machine
    // ------------------------------------------------------------------------

    typedef enum logic [4:0] {
        SYNC0,
        SYNC1,

        SEQ,
        CMD,
        LENHI,
        LENLO,
        PAYLOAD,
        CRCHI,
        CRCLO,

        DROP,
        EXEC,

        WRITE_WORD,
        READ_REQUEST,
        READ_WAIT,

        START_WAIT,
        RESET_HOLD,

        TX_PREP,
        TX_SEND,
        TX_DRAIN
    } state_t;

    state_t state;


    // ------------------------------------------------------------------------
    // Packet information
    // ------------------------------------------------------------------------

    logic [7:0] sequence_id;
    logic [7:0] command;
    logic [7:0] crc_hi;
    logic [7:0] response_status;

    logic [15:0] request_len;
    logic [15:0] response_len;

    logic [15:0] rx_crc;
    logic [15:0] tx_crc;

    logic [8:0] byte_idx;
    logic [8:0] tx_idx;

    // Number of bytes remaining when discarding an oversized packet.
    logic [16:0] discard_left;

    logic [TW-1:0] timeout_count;


    // ------------------------------------------------------------------------
    // Packet payload storage
    // ------------------------------------------------------------------------

    logic [7:0] payload  [0:MAX_PAYLOAD-1];
    logic [7:0] response [0:4*MAX_WORDS-1];


    // ------------------------------------------------------------------------
    // Memory transaction information
    // ------------------------------------------------------------------------

    logic [15:0] base_addr;
    logic [15:0] word_count;
    logic [6:0]  word_idx;
    logic [1:0]  bank;


    // ------------------------------------------------------------------------
    // Accelerator control/status
    // ------------------------------------------------------------------------

    logic        soft_reset;
    logic [2:0]  reset_count;

    // Counts the number of accelerator clock cycles spent busy.
    logic [31:0] busy_cycles;

    // Indicates that the FSM is currently receiving a packet.
    logic collecting;


    // ------------------------------------------------------------------------
    // Parsed request fields
    // ------------------------------------------------------------------------

    // Memory command payload:
    //      payload[0]   = bank
    //      payload[1:2] = base address
    //      payload[3:4] = number of words
    wire [15:0] req_addr  = {payload[1], payload[2]};
    wire [15:0] req_words = {payload[3], payload[4]};

    // START command payload:
    //      payload[0:1] = sequence length
    wire [15:0] req_seq_len = {payload[0], payload[1]};

    // ------------------------------------------------------------------------
    // CRC-16/CCITT-FALSE
    // ------------------------------------------------------------------------
    //
    // Processes one byte and returns the updated CRC value.

    function automatic logic [15:0] crc_byte(
        input logic [15:0] crc,
        input logic [7:0]  value
    );
        logic [15:0] c;

        // XOR the next byte into the upper half of the CRC register.
        c = crc ^ {value, 8'b0};

        // Process each bit using polynomial 0x1021.
        for (int i = 0; i < 8; i++) begin
            c = c[15] ? (c << 1) ^ 16'h1021 : (c << 1);
        end
        return c;
    endfunction

    // ------------------------------------------------------------------------
    // Response helper
    // ------------------------------------------------------------------------
    //
    // Stores the response status/length and moves the FSM into transmission.
    // Any non-OK response also latches the error output.

    task automatic reply(
        input logic [7:0]  status,
        input logic [15:0] length
    );
        response_status <= status;
        response_len    <= length;
        state           <= TX_PREP;

        if (status != OK)
            error_latched <= 1;
    endtask

    // ------------------------------------------------------------------------
    // Control outputs
    // ------------------------------------------------------------------------

    // Receive timeout logic is active while collecting a packet.
    assign collecting = (state >= SEQ && state <= CRCLO) || state == DROP || state == SYNC1;

    // Soft reset only resets the accelerator core.
    // UART communication remains active.
    assign core_rst_n = rst_n && !soft_reset;

    // ------------------------------------------------------------------------
    // Host buffer interface
    // ------------------------------------------------------------------------

    // A request remains asserted until the memory interface accepts it.
    assign host_req = (state == WRITE_WORD || state == READ_REQUEST);

    // WRITE_WORD selects a write transaction.
    assign host_we = (state == WRITE_WORD);

    assign host_bank = bank;

    // Each transaction advances one 32-bit word from the base address.
    assign host_addr = BUF_ADDR_W'(int'(base_addr) + int'(word_idx));

    // Build a 32-bit write word from four big-endian payload bytes.
    always_comb begin
        host_wdata = '0;

        if (state == WRITE_WORD) begin
            for (int b = 0; b < 4; b++) begin
                host_wdata[31-b*8 -: 8] = payload[5 + int'(word_idx)*4 + b];
            end
        end
    end

    // ------------------------------------------------------------------------
    // UART transmit datapath
    // ------------------------------------------------------------------------

    // tx_valid is asserted for every byte sent in TX_SEND.
    assign tx_valid = (state == TX_SEND);

    // Select the byte currently being transmitted.
    always_comb begin
        tx_data = 0;
        
        case (tx_idx)
            // Response synchronization bytes.
            0: tx_data = 8'h5A;
            1: tx_data = 8'hA5;

            // Response header.
            2: tx_data = sequence_id;
            3: tx_data = response_status;
            4: tx_data = response_len[15:8];
            5: tx_data = response_len[7:0];

            default: begin
                // Response payload.
                if (int'(tx_idx) < 6 + int'(response_len)) begin
                    tx_data = response[int'(tx_idx) - 6];
                end

                // CRC high byte.
                else if (int'(tx_idx) == 6 + int'(response_len)) begin
                    tx_data = tx_crc[15:8];
                end

                // CRC low byte.
                else begin
                    tx_data = tx_crc[7:0];
                end
            end
        endcase
    end

    // ------------------------------------------------------------------------
    // Main command processor
    // ------------------------------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= SYNC0;

            sequence_id     <= 0;
            command         <= 0;
            crc_hi          <= 0;
            response_status <= 0;

            request_len     <= 0;
            response_len    <= 0;

            rx_crc          <= 16'hFFFF;
            tx_crc          <= 16'hFFFF;

            byte_idx        <= 0;
            tx_idx          <= 0;

            discard_left    <= 0;
            timeout_count   <= 0;

            base_addr       <= 0;
            word_count      <= 0;
            word_idx        <= 0;
            bank            <= 0;

            soft_reset      <= 0;
            reset_count     <= 0;

            busy_cycles     <= 0;

            start           <= 0;
            tile_sq_len     <= 0;

            done_latched    <= 0;
            error_latched   <= 0;
        end else begin
            // START is a one-cycle pulse.
            start <= 0;

            // ----------------------------------------------------------------
            // Accelerator status tracking
            // ----------------------------------------------------------------

            if (done) begin
                done_latched <= 1;
            end

            if (config_error) begin
                error_latched <= 1;
            end

            // Measure accelerator execution time.
            if (busy) begin
                busy_cycles <= busy_cycles + 1'b1;
            end

            // ----------------------------------------------------------------
            // Receive timeout tracking
            // ----------------------------------------------------------------

            // Reset the timeout whenever a byte arrives or the FSM is not
            // currently receiving a packet.
            if (!collecting || rx_valid) begin
                timeout_count <= 0;
            end else begin
                timeout_count <= timeout_count + 1'b1;
            end

            // ----------------------------------------------------------------
            // Receive errors and timeout handling
            // ----------------------------------------------------------------
            if (rx_error && collecting) begin

                timeout_count <= 0;
                reply(BAD_FRAME, 0);

            end else if (collecting && !rx_valid && timeout_count == TW'(RX_TIMEOUT_CYCLES - 1)) begin
                timeout_count <= 0;

                // A timeout while looking for the second sync byte simply
                // returns the receiver to its idle state.
                if (state == SYNC1) begin
                    state <= SYNC0;
                end

                // An incomplete oversized frame is reported as BAD_LENGTH.
                else if (state == DROP) begin
                    reply(BAD_LENGTH, 0);
                end

                // Any other incomplete packet is a normal receive timeout.
                else begin
                    reply(RX_TIMEOUT, 0);
                end

            end else begin
                case (state)
                    // ========================================================
                    // Packet synchronization
                    // ========================================================

                    // Wait for first sync byte: A5.
                    SYNC0: begin
                        if (rx_valid && rx_data == 8'hA5) begin
                            state <= SYNC1;
                        end
                    end

                    // Wait for second sync byte: 5A.
                    //
                    // Another A5 keeps the receiver in SYNC1 so that repeated
                    // A5 bytes can still lead into a valid packet.
                    SYNC1: begin
                        if (rx_valid) begin
                            if (rx_data == 8'h5A) begin
                                state  <= SEQ;
                                rx_crc <= 16'hFFFF;
                            end else if (rx_data != 8'hA5) begin
                                state <= SYNC0;
                            end
                        end
                    end

                    // ========================================================
                    // Request header
                    // ========================================================
                    // Sequence ID.
                    SEQ: begin
                        if (rx_valid) begin
                            sequence_id <= rx_data;
                            rx_crc      <= crc_byte(rx_crc, rx_data);
                            state       <= CMD;
                        end
                    end

                    // Command byte.
                    CMD: begin
                        if (rx_valid) begin
                            command <= rx_data;
                            rx_crc  <= crc_byte(rx_crc, rx_data);
                            state   <= LENHI;
                        end
                    end

                    // Payload length, high byte.
                    LENHI: begin
                        if (rx_valid) begin
                            request_len[15:8] <= rx_data;
                            rx_crc            <= crc_byte(rx_crc, rx_data);
                            state             <= LENLO;
                        end
                    end

                    // Payload length, low byte.
                    LENLO: begin
                        if (rx_valid) begin
                            request_len[7:0] <= rx_data;
                            rx_crc           <= crc_byte(rx_crc, rx_data);
                            byte_idx         <= 0;

                            // Reject payloads larger than the local buffer.
                            if ({request_len[15:8], rx_data} > 16'(MAX_PAYLOAD)) begin
                                // Remaining payload bytes plus the two CRC bytes
                                // must be consumed before accepting a new packet.
                                discard_left <= {1'b0, request_len[15:8], rx_data} + 17'd2;
                                state <= DROP;
                            end else begin
                                // Skip PAYLOAD for zero-length commands.
                                state <= ({request_len[15:8], rx_data} == 0) ? CRCHI : PAYLOAD;
                            end
                        end
                    end

                    // ========================================================
                    // Request payload
                    // ========================================================
                    PAYLOAD: begin
                        if (rx_valid) begin

                            payload[byte_idx] <= rx_data;
                            rx_crc            <= crc_byte(rx_crc, rx_data);

                            // Move to CRC after the final payload byte.
                            if (16'(byte_idx) + 16'd1 == request_len) begin
                                state <= CRCHI;
                            end else begin
                                byte_idx <= byte_idx + 1'b1;
                            end
                        end
                    end

                    // ========================================================
                    // Request CRC
                    // ========================================================

                    // Receive CRC high byte.
                    CRCHI: begin
                        if (rx_valid) begin
                            crc_hi <= rx_data;
                            state  <= CRCLO;
                        end
                    end

                    // Receive CRC low byte and validate the complete frame.
                    CRCLO: begin
                        if (rx_valid) begin
                            if ({crc_hi, rx_data} == rx_crc) begin
                                state <= EXEC;
                            end else begin
                                reply(BAD_CRC, 0);
                            end
                        end
                    end

                    // ========================================================
                    // Oversized packet handling
                    // ========================================================
                    // Consume the remainder of an oversized frame so that the
                    // UART stream becomes aligned with the next packet.
                    DROP: begin
                        if (rx_valid) begin
                            if (discard_left == 1) begin
                                reply(BAD_LENGTH, 0);
                            end else begin
                                discard_left <= discard_left - 1'b1;
                            end
                        end
                    end

                    // ========================================================
                    // Execute command
                    // ========================================================
                    EXEC: begin
                        case (command)
                            // ------------------------------------------------
                            // WRITE / READ BUFFER
                            // ------------------------------------------------
                            
                            // Payload:
                            //
                            //      Byte 0   : buffer bank
                            //      Byte 1-2 : base address
                            //      Byte 3-4 : word count
                            // WRITE additionally contains 4 bytes per word.
                            8'h01,
                            8'h02: begin
                                if (request_len < 5) begin
                                    reply(BAD_ARGUMENT, 0);
                                end else if (
                                    payload[0] > 3 ||
                                    req_words == 0 ||
                                    req_words > 16'(MAX_WORDS) ||

                                    ({1'b0, req_addr} +
                                     {1'b0, req_words}) >
                                        17'(BUF_DEPTH) ||

                                    (
                                        command == 1 &&
                                        (
                                            payload[0] == 3 ||
                                            int'(request_len) !=
                                                5 + 4 * int'(req_words)
                                        )
                                    ) ||

                                    (
                                        command == 2 &&
                                        request_len != 5
                                    )
                                ) begin
                                    reply(BAD_ARGUMENT, 0);
                                end else if (busy || done) begin
                                    // Buffer access is blocked while the core
                                    // is active or waiting to be reset.
                                    reply(IS_BUSY, 0);
                                end else begin
                                    bank       <= payload[0][1:0];
                                    base_addr  <= req_addr;
                                    word_count <= req_words;
                                    word_idx   <= 0;

                                    if (command == 1) begin
                                        state <= WRITE_WORD;
                                    end else begin
                                        state <= READ_REQUEST;
                                    end
                                end
                            end

                            // ------------------------------------------------
                            // START ACCELERATOR
                            // ------------------------------------------------
                            // Payload:
                            //
                            //      Byte 0-1 : sequence length
                            8'h03: begin
                                if (request_len != 2 ||
                                    req_seq_len == 0 ||
                                    req_seq_len > 16'(MAX_TOKENS) ||
                                    (int'(req_seq_len) % BATCH_SIZE) != 0
                                ) begin
                                    reply(BAD_ARGUMENT, 0);
                                end else if (busy || done) begin
                                    reply(IS_BUSY, 0);
                                end else begin

                                    tile_sq_len <=  MAX_TILE_SQ_LEN_W'(req_seq_len);

                                    // Generate one-cycle accelerator start pulse.
                                    start <= 1;

                                    done_latched <= 0;
                                    busy_cycles  <= 0;

                                    state <= START_WAIT;
                                end
                            end

                            // ------------------------------------------------
                            // STATUS / CAPABILITIES
                            // ------------------------------------------------
                            // Returns a fixed 22-byte big-endian response
                            // describing the accelerator and its current state.
                            8'h04: begin
                                if (request_len != 0) begin
                                    reply(BAD_ARGUMENT, 0);
                                end else begin
                                    // "FA" protocol identifier.
                                    response[0] <= 8'h46;
                                    response[1] <= 8'h41;

                                    // Protocol version.
                                    response[2] <= 1;

                                    // Current status flags.
                                    response[3] <= {
                                        5'b0,
                                        error_latched,
                                        done_latched,
                                        busy
                                    };

                                    // Accelerator configuration.
                                    response[4] <= 8'(OPERAND_W);
                                    response[5] <= 8'(D_MODEL);
                                    response[6] <= 8'(BATCH_SIZE);
                                    response[7] <= 8'(MAX_WORDS);

                                    // Buffer depth.
                                    response[8] <= 8'(BUF_DEPTH >> 8);
                                    response[9] <= 8'(BUF_DEPTH);

                                    // Maximum supported token count.
                                    response[10] <= 8'(MAX_TOKENS >> 8);
                                    response[11] <= 8'(MAX_TOKENS);

                                    // Accelerator clock frequency.
                                    response[12] <= 8'(CLK_HZ >> 24);
                                    response[13] <= 8'(CLK_HZ >> 16);
                                    response[14] <= 8'(CLK_HZ >> 8);
                                    response[15] <= 8'(CLK_HZ);

                                    // Number of cycles spent busy.
                                    response[16] <= busy_cycles[31:24];
                                    response[17] <= busy_cycles[23:16];
                                    response[18] <= busy_cycles[15:8];
                                    response[19] <= busy_cycles[7:0];

                                    // Fixed-point fractional precision.
                                    response[20] <= 8'(FRAC_BITS);

                                    // Fixed Q/K stride.
                                    response[21] <= 0;
                                    reply(OK, 22);
                                end
                            end

                            // ------------------------------------------------
                            // SOFT RESET
                            // ------------------------------------------------
                            //
                            // Resets the compute core while preserving buffer
                            // contents and the UART command processor.
                            8'h05: begin
                                if (request_len != 0) begin
                                    reply(BAD_ARGUMENT, 0);
                                end else begin
                                    soft_reset    <= 1;
                                    reset_count   <= 0;

                                    done_latched  <= 0;
                                    error_latched <= 0;
                                    busy_cycles   <= 0;

                                    state <= RESET_HOLD;
                                end
                            end

                            // Unknown command opcode.
                            default: begin
                                reply(BAD_COMMAND, 0);
                            end
                        endcase
                    end

                    // ========================================================
                    // Buffer write
                    // ========================================================
                    // Present one 32-bit word to the buffer interface and wait
                    // until the transaction is accepted.
                    WRITE_WORD: begin
                        if (host_ready) begin
                            // Last word completes the command.
                            if (16'(word_idx) + 16'd1 == word_count) begin
                                reply(OK, 0);
                            end else begin
                                word_idx <= word_idx + 1'b1;
                            end
                        end
                    end

                    // ========================================================
                    // Buffer read
                    // ========================================================
                    // Send one read request.
                    READ_REQUEST: begin
                        if (host_ready) begin
                            state <= READ_WAIT;
                        end
                    end

                    // Wait for the corresponding read data.
                    READ_WAIT: begin
                        if (host_rsp_valid) begin
                            // Store the 32-bit result as four big-endian bytes.
                            for (int b = 0; b < 4; b++) begin
                                response[int'(word_idx)*4 + b] <= host_rdata[31-b*8 -: 8];
                            end

                            // Final read completes the response.
                            if (16'(word_idx) + 16'd1 == word_count) begin
                                reply(OK, word_count << 2);
                            end else begin
                                word_idx <= word_idx + 1'b1;
                                state    <= READ_REQUEST;
                            end
                        end
                    end

                    // ========================================================
                    // Accelerator start completion
                    // ========================================================
                    // START has already been pulsed for one cycle.
                    // Return success to the host.
                    START_WAIT: begin
                        reply(OK, 0);
                    end

                    // ========================================================
                    // Soft reset
                    // ========================================================
                    // Hold the compute core in reset for several clock cycles.
                    RESET_HOLD: begin
                        done_latched <= 0;
                        busy_cycles  <= 0;
                        if (reset_count == 3) begin
                            soft_reset <= 0;
                            reply(OK, 0);
                        end else begin
                            reset_count <= reset_count + 1'b1;
                        end
                    end

                    // ========================================================
                    // Response transmission
                    // ========================================================
                    // Initialize response transmission and CRC generation.
                    TX_PREP: begin
                        tx_idx <= 0;
                        tx_crc <= 16'hFFFF;
                        state  <= TX_SEND;
                    end

                    // Send one response byte whenever the UART transmitter is
                    // ready to accept it.
                    TX_SEND: begin
                        if (tx_ready) begin
                            // CRC covers sequence ID through the final payload
                            // byte. The two synchronization bytes are excluded.
                            if (tx_idx >= 2 && int'(tx_idx) < 6 + int'(response_len)) begin
                                tx_crc <= crc_byte(tx_crc, tx_data);
                            end

                            // Final byte is CRC low.
                            if (int'(tx_idx) == 7 + int'(response_len)) begin
                                state <= TX_DRAIN;
                            end else begin
                                tx_idx <= tx_idx + 1'b1;
                            end
                        end
                    end


                    // Wait for the UART interface to finish accepting the final
                    // transmitted byte before returning to idle.
                    TX_DRAIN: begin
                        if (tx_ready) begin
                            state <= SYNC0;
                        end
                    end

                    // Recovery path for an invalid FSM state.
                    default: begin
                        state <= SYNC0;
                    end
                endcase
            end
        end
    end
endmodule