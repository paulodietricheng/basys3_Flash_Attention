`timescale 1ns/1ps
// SIMULATION ONLY: true functions rounded to a temporary Q16 representation.
// Scores are raw integer QK products; exp applies the standard 1/sqrt(16)=1/4
// attention score scale. DO NOT synthesize these $exp/$floor implementations.
module exp (
    input logic clk, rst_n, start,
    output logic busy, done,
    input logic [31:0] in,
    output logic [31:0] out
);
    logic signed [31:0] saved;
    int delay_left;
    real value;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin busy<=0;done<=0;out<=0;saved<=0;delay_left<=0;end
        else begin
            done<=0;
            if(start && !busy) begin
                saved<=$signed(in);busy<=1;delay_left<=1+int'(in[1:0]);
            end else if(busy) begin
                if(delay_left==0) begin
                    value=$exp(real'(saved)/4.0)*65536.0;
                    out<=32'($rtoi($floor(value+0.5)));
                    busy<=0;done<=1;
                end else delay_left<=delay_left-1;
            end
        end
    end
endmodule
module rcp (
    input logic clk, rst_n, start,
    output logic busy, done,
    input logic [31:0] in,
    output logic [31:0] out
);
    logic signed [31:0] saved;
    int delay_left;
    real value;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin busy<=0;done<=0;out<=0;saved<=0;delay_left<=0;end
        else begin
            done<=0;
            if(start && !busy) begin
                saved<=$signed(in);busy<=1;delay_left<=2+int'(in[1:0]);
            end else if(busy) begin
                if(delay_left==0) begin
                    assert(saved>0) else $fatal(1,"Invalid attention denominator");
                    value=4294967296.0/real'(saved);
                    out<=32'($rtoi($floor(value+0.5)));
                    busy<=0;done<=1;
                end else delay_left<=delay_left-1;
            end
        end
    end
endmodule
