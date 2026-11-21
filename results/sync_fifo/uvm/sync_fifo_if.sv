`timescale 1ns/1ps
interface sync_fifo_if (input logic clk);
    logic rst_n;
    logic wr_valid;
    logic [7:0] wr_data;
    logic rd_ready;
    logic wr_ready;
    logic rd_valid;
    logic [7:0] rd_data;
    logic [3:0] count;
endinterface
