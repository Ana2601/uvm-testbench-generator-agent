`timescale 1ns/1ps
interface seq_mult_if (input logic clk);
    logic rst_n;
    logic start;
    logic [15:0] a;
    logic [15:0] b;
    logic busy;
    logic done;
    logic [31:0] p;
endinterface
