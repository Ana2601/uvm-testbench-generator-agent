`timescale 1ns/1ps
interface uart_tx_buggy_if (input logic clk);
    logic rst_n;
    logic tx_valid;
    logic [7:0] tx_data;
    logic tx_ready;
    logic txd;
endinterface
