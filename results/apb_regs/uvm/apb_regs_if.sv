`timescale 1ns/1ps
interface apb_regs_if (input logic pclk);
    logic presetn;
    logic psel;
    logic penable;
    logic pwrite;
    logic [3:0] paddr;
    logic [31:0] pwdata;
    logic [31:0] prdata;
    logic pready;
    logic pslverr;
endinterface
