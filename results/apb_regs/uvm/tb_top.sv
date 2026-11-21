`timescale 1ns/1ps
module tb_top;
    import uvm_pkg::*;
    import apb_regs_tb_pkg::*;
    logic pclk = 1'b0;
    always #5.0 pclk = ~pclk;
    apb_regs_if ifc (pclk);
    initial ifc.presetn = 1'b0;
    apb_regs dut (.pclk(pclk), .presetn(ifc.presetn), .psel(ifc.psel), .penable(ifc.penable), .pwrite(ifc.pwrite), .paddr(ifc.paddr), .pwdata(ifc.pwdata), .prdata(ifc.prdata), .pready(ifc.pready), .pslverr(ifc.pslverr));
    initial begin
        uvm_config_db #(virtual apb_regs_if)::set(null, "*", "vif", ifc);
        run_test("apb_regs_test");
    end
endmodule
