`timescale 1ns/1ps
module tb_bram;
    logic clk=0;
    always #5 clk=~clk;
    logic [31:0] din_a=0, din_b=0, dout_a, dout_b;
    logic [9:0] addr_a=0, addr_b=1;
    logic we_a=0, we_b=0;
    logic [31:0] expected[0:1023];

    bram #(.INIT_FILE("fixtures/dummy_fixed/000/q.hex")) dut (.*);

    initial begin
        $readmemh("fixtures/dummy_fixed/000/q.hex",expected);
        @(negedge clk);
        assert(dout_a===expected[0] && dout_b===expected[1]) else $fatal(1,"BRAM initialization/read");
        addr_a=1022;addr_b=1023;
        @(negedge clk);
        assert(dout_a===expected[1022] && dout_b===expected[1023]) else $fatal(1,"BRAM high address");
        addr_a=0;addr_b=1;din_a=32'h12345678;din_b=32'hfedcba98;we_a=1;we_b=1;
        @(negedge clk);
        assert(dout_a===expected[0] && dout_b===expected[1]) else $fatal(1,"BRAM read-first behavior");
        we_a=0;we_b=0;
        @(negedge clk);
        assert(dout_a===32'h12345678 && dout_b===32'hfedcba98) else $fatal(1,"BRAM dual write/read");
        // Write A while reading an independent address through B.
        we_a=1;din_a=32'haabbccdd;
        @(negedge clk);
        assert(dout_a===32'h12345678 && dout_b===32'hfedcba98) else $fatal(1,"BRAM independent ports");
        we_a=0;addr_b=0;
        @(negedge clk);
        assert(dout_a===32'haabbccdd && dout_b===32'haabbccdd) else $fatal(1,"BRAM same-address reads");
        din_a=0;din_b=0;
        repeat(3) @(negedge clk);
        assert(dout_a===32'haabbccdd && dout_b===32'haabbccdd) else $fatal(1,"BRAM write enable ignored");
        $display("PASS BRAM init, latency, read-first, independent ports and write enables");
        $finish;
    end
endmodule
