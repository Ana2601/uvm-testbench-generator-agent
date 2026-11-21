`timescale 1ns/1ps
package apb_regs_tb_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    class apb_regs_item extends uvm_sequence_item;
        `uvm_object_utils(apb_regs_item)
        logic presetn;
        logic psel;
        logic penable;
        logic pwrite;
        logic [3:0] paddr;
        logic [31:0] pwdata;
        logic [31:0] prdata;
        logic pready;
        logic pslverr;
        function new(string name = "apb_regs_item"); super.new(name); endfunction
        function string convert2string(); return $sformatf("presetn=%0h psel=%0h penable=%0h pwrite=%0h paddr=%0h pwdata=%0h prdata=%0h pready=%0h pslverr=%0h", presetn, psel, penable, pwrite, paddr, pwdata, prdata, pready, pslverr); endfunction
    endclass

    class apb_regs_reset_seq extends uvm_sequence #(apb_regs_item);
        `uvm_object_utils(apb_regs_reset_seq)
        function new(string name = "apb_regs_reset_seq"); super.new(name); endfunction
        task body();
            repeat (3) begin
                apb_regs_item t = apb_regs_item::type_id::create("t");
                start_item(t);
                t.psel = 1'b0;
                t.penable = 1'b0;
                t.pwrite = 1'b0;
                t.paddr = 4'h0;
                t.pwdata = 32'h0;
                t.presetn = 1'b0;
                finish_item(t);
            end
        endtask
    endclass

    class apb_regs_random_mapped_transfers_seq extends uvm_sequence #(apb_regs_item);
        `uvm_object_utils(apb_regs_random_mapped_transfers_seq)
        int i;
        logic [3:0] s_addr;
        bit s_wr;
        logic [31:0] s_data;
        function new(string name = "apb_regs_random_mapped_transfers_seq"); super.new(name); endfunction
        task body();
            for (i = 0; i < 4000; i++) begin
                apb_regs_item t = apb_regs_item::type_id::create("t");
                start_item(t);
                t.psel = 1'b0;
                t.penable = 1'b0;
                t.pwrite = 1'b0;
                t.paddr = 4'h0;
                t.pwdata = 32'h0;
                if (i % 2 == 0) begin
                    s_addr = 4'($urandom_range(0, 3) * 4);
                    s_wr   = 1'($urandom_range(0, 1));
                    s_data = $urandom;
                end
                t.psel = 1'b1;
                t.penable = 1'(i % 2);
                t.pwrite = s_wr;
                t.paddr = s_addr;
                t.pwdata = s_data;
                t.presetn = 1'b1;
                finish_item(t);
            end
        endtask
    endclass

    class apb_regs_all_addresses_with_idle_seq extends uvm_sequence #(apb_regs_item);
        `uvm_object_utils(apb_regs_all_addresses_with_idle_seq)
        int i;
        logic [3:0] s_addr;
        bit s_wr;
        logic [31:0] s_data;
        function new(string name = "apb_regs_all_addresses_with_idle_seq"); super.new(name); endfunction
        task body();
            for (i = 0; i < 3000; i++) begin
                apb_regs_item t = apb_regs_item::type_id::create("t");
                start_item(t);
                t.psel = 1'b0;
                t.penable = 1'b0;
                t.pwrite = 1'b0;
                t.paddr = 4'h0;
                t.pwdata = 32'h0;
                if (i % 3 == 0) begin
                    s_addr = 4'($urandom_range(0, 15));
                    s_wr   = 1'($urandom_range(0, 1));
                    s_data = $urandom;
                end
                t.psel = 1'(i % 3 != 2);
                t.penable = 1'(i % 3 == 1);
                t.pwrite = s_wr;
                t.paddr = s_addr;
                t.pwdata = s_data;
                t.presetn = 1'b1;
                finish_item(t);
            end
        endtask
    endclass

    class apb_regs_reset_then_read_all_seq extends uvm_sequence #(apb_regs_item);
        `uvm_object_utils(apb_regs_reset_then_read_all_seq)
        int i;
        logic [3:0] s_addr;
        bit s_wr;
        logic [31:0] s_data;
        function new(string name = "apb_regs_reset_then_read_all_seq"); super.new(name); endfunction
        task body();
            for (i = 0; i < 400; i++) begin
                apb_regs_item t = apb_regs_item::type_id::create("t");
                start_item(t);
                t.psel = 1'b0;
                t.penable = 1'b0;
                t.pwrite = 1'b0;
                t.paddr = 4'h0;
                t.pwdata = 32'h0;
                if (i % 2 == 0) begin
                    // every 40 cycles: 10 random writes, reset, then read all four registers
                    s_wr   = 1'((i % 40) < 20);
                    s_addr = 4'((i % 8) * 2);
                    s_data = $urandom;
                end
                t.psel = 1'b1;
                t.penable = 1'(i % 2);
                t.pwrite = s_wr;
                t.paddr = s_addr;
                t.pwdata = s_data;
                t.presetn = ((i % 40) == 20) ? 1'b0 : 1'b1;
                finish_item(t);
            end
        endtask
    endclass

    class apb_regs_driver extends uvm_driver #(apb_regs_item);
        `uvm_component_utils(apb_regs_driver)
        virtual apb_regs_if vif;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            if (!uvm_config_db #(virtual apb_regs_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "virtual interface not set")
        endfunction
        task run_phase(uvm_phase phase);
            forever begin
                seq_item_port.get_next_item(req);
                @(negedge vif.pclk);
                vif.presetn = req.presetn;
                vif.psel = req.psel;
                vif.penable = req.penable;
                vif.pwrite = req.pwrite;
                vif.paddr = req.paddr;
                vif.pwdata = req.pwdata;
                seq_item_port.item_done();
            end
        endtask
    endclass

    class apb_regs_monitor extends uvm_monitor;
        `uvm_component_utils(apb_regs_monitor)
        virtual apb_regs_if vif;
        uvm_analysis_port #(apb_regs_item) ap;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            ap = new("ap", this);
            if (!uvm_config_db #(virtual apb_regs_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "virtual interface not set")
        endfunction
        task run_phase(uvm_phase phase);
            forever begin
                apb_regs_item t;
                @(negedge vif.pclk);
                #1;
                t = apb_regs_item::type_id::create("t");
                t.presetn = vif.presetn;
                t.psel = vif.psel;
                t.penable = vif.penable;
                t.pwrite = vif.pwrite;
                t.paddr = vif.paddr;
                t.pwdata = vif.pwdata;
                t.prdata = vif.prdata;
                t.pready = vif.pready;
                t.pslverr = vif.pslverr;
                ap.write(t);
            end
        endtask
    endclass

    class apb_regs_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(apb_regs_scoreboard)
        uvm_analysis_imp #(apb_regs_item, apb_regs_scoreboard) imp;
        // port mirrors: the plan's model and coverage code refer to ports by name
        logic presetn;
        logic psel;
        logic penable;
        logic pwrite;
        logic [3:0] paddr;
        logic [31:0] pwdata;
        logic [31:0] prdata;
        logic pready;
        logic pslverr;
        logic [31:0] exp_prdata;
        bit   chk_prdata;
        logic exp_pready;
        bit   chk_pready;
        logic exp_pslverr;
        bit   chk_pslverr;
        int errors = 0, checks = 0;
        int cov_hits [11];
        // ---- reference model (from the plan) ----
        logic [7:0]  m_ctrl;
        logic [31:0] m_data;
        logic [15:0] m_wcnt;
        logic [1:0]  m_stat;
        bit m_access, m_mapped;
        bit m_dirty_at_reset;
        function void m_reset();
            m_dirty_at_reset = (m_ctrl != 8'h00) || (m_data != 32'h0) || (m_wcnt != 16'h0) || (m_stat != 2'b00);
            m_ctrl = 8'h00;
            m_data = 32'h0;
            m_wcnt = 16'h0;
            m_stat = 2'b00;
        endfunction
        function void m_outputs();
            chk_prdata = 1'b1;
            chk_pready = 1'b1;
            chk_pslverr = 1'b1;
            m_access = psel && penable;
            m_mapped = (paddr == 4'h0) || (paddr == 4'h4) || (paddr == 4'h8) || (paddr == 4'hC);
            exp_pready  = 1'b1;
            exp_pslverr = m_access && (!m_mapped || (pwrite && paddr == 4'h8));
            case (paddr)
                4'h0:    exp_prdata = {24'h0, m_ctrl};
                4'h4:    exp_prdata = m_data;
                4'h8:    exp_prdata = {16'h0, m_wcnt};
                4'hC:    exp_prdata = {30'h0, m_stat};
                default: exp_prdata = 32'h0;
            endcase
            // prdata is only defined in the access phase of a successful read
            chk_prdata = m_access && !pwrite && !exp_pslverr;
        endfunction
        function void m_step();
            if (m_access && pwrite && !exp_pslverr) begin
                case (paddr)
                    4'h0: begin m_ctrl = pwdata[7:0]; m_stat[1] = 1'b1; end
                    4'h4: begin m_data = pwdata; m_wcnt = m_wcnt + 16'h1; m_stat[0] = 1'b1; end
                    4'hC: m_stat = m_stat & ~pwdata[1:0];
                    default: ;
                endcase
            end
        endfunction
        function new(string name, uvm_component parent);
            super.new(name, parent);
            imp = new("imp", this);
        endfunction
        function void write(apb_regs_item t);
            presetn = t.presetn;
            psel = t.psel;
            penable = t.penable;
            pwrite = t.pwrite;
            paddr = t.paddr;
            pwdata = t.pwdata;
            prdata = t.prdata;
            pready = t.pready;
            pslverr = t.pslverr;
            if (presetn == 1'b0) m_reset();
            m_outputs();
            checks++;
            if (chk_prdata && (prdata !== exp_prdata)) begin
                errors++;
                if (errors <= 12)
                    `uvm_error("SCB", $sformatf("MISMATCH cycle=%0d port=prdata got=%0h exp=%0h | %s", checks, prdata, exp_prdata, t.convert2string()))
            end
            if (chk_pready && (pready !== exp_pready)) begin
                errors++;
                if (errors <= 12)
                    `uvm_error("SCB", $sformatf("MISMATCH cycle=%0d port=pready got=%0h exp=%0h | %s", checks, pready, exp_pready, t.convert2string()))
            end
            if (chk_pslverr && (pslverr !== exp_pslverr)) begin
                errors++;
                if (errors <= 12)
                    `uvm_error("SCB", $sformatf("MISMATCH cycle=%0d port=pslverr got=%0h exp=%0h | %s", checks, pslverr, exp_pslverr, t.convert2string()))
            end
            if (psel && penable && pwrite && paddr == 4'h0) cov_hits[0]++;
            if (psel && penable && pwrite && paddr == 4'h4) cov_hits[1]++;
            if (psel && penable && pwrite && paddr == 4'hC && (pwdata[1:0] & m_stat) != 2'b00) cov_hits[2]++;
            if (psel && penable && !pwrite && paddr == 4'h0) cov_hits[3]++;
            if (psel && penable && !pwrite && paddr == 4'h4) cov_hits[4]++;
            if (psel && penable && !pwrite && paddr == 4'h8 && m_wcnt != 16'h0) cov_hits[5]++;
            if (psel && penable && !pwrite && paddr == 4'hC && m_stat == 2'b11) cov_hits[6]++;
            if (pslverr && pwrite && paddr == 4'h8) cov_hits[7]++;
            if (pslverr && paddr != 4'h0 && paddr != 4'h4 && paddr != 4'h8 && paddr != 4'hC) cov_hits[8]++;
            if (!psel) cov_hits[9]++;
            if (!presetn && m_dirty_at_reset) cov_hits[10]++;
            if (presetn != 1'b0) m_step();
        endfunction
        function void report_phase(uvm_phase phase);
            $display("COVER write_ctrl %0d", cov_hits[0]);
            $display("COVER write_data %0d", cov_hits[1]);
            $display("COVER write_stat_clear %0d", cov_hits[2]);
            $display("COVER read_ctrl %0d", cov_hits[3]);
            $display("COVER read_data %0d", cov_hits[4]);
            $display("COVER read_wcnt %0d", cov_hits[5]);
            $display("COVER read_stat_set %0d", cov_hits[6]);
            $display("COVER error_write_wcnt %0d", cov_hits[7]);
            $display("COVER error_unmapped %0d", cov_hits[8]);
            $display("COVER idle_cycle %0d", cov_hits[9]);
            $display("COVER reset_after_writes %0d", cov_hits[10]);
            $display("CHECKS %0d ERRORS %0d", checks, errors);
            if (errors == 0) $display("PASS"); else $display("FAIL");
        endfunction
    endclass

    class apb_regs_agent extends uvm_agent;
        `uvm_component_utils(apb_regs_agent)
        uvm_sequencer #(apb_regs_item) sqr;
        apb_regs_driver  drv;
        apb_regs_monitor mon;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            sqr = uvm_sequencer #(apb_regs_item)::type_id::create("sqr", this);
            drv = apb_regs_driver::type_id::create("drv", this);
            mon = apb_regs_monitor::type_id::create("mon", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass

    class apb_regs_env extends uvm_env;
        `uvm_component_utils(apb_regs_env)
        apb_regs_agent      agt;
        apb_regs_scoreboard scb;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            agt = apb_regs_agent::type_id::create("agt", this);
            scb = apb_regs_scoreboard::type_id::create("scb", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            agt.mon.ap.connect(scb.imp);
        endfunction
    endclass

    class apb_regs_test extends uvm_test;
        `uvm_component_utils(apb_regs_test)
        apb_regs_env env;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            env = apb_regs_env::type_id::create("env", this);
        endfunction
        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            begin apb_regs_reset_seq s = apb_regs_reset_seq::type_id::create("s"); s.start(env.agt.sqr); end
            begin apb_regs_random_mapped_transfers_seq s = apb_regs_random_mapped_transfers_seq::type_id::create("s"); s.start(env.agt.sqr); end
            begin apb_regs_all_addresses_with_idle_seq s = apb_regs_all_addresses_with_idle_seq::type_id::create("s"); s.start(env.agt.sqr); end
            begin apb_regs_reset_then_read_all_seq s = apb_regs_reset_then_read_all_seq::type_id::create("s"); s.start(env.agt.sqr); end
            #20;
            phase.drop_objection(this);
        endtask
    endclass
endpackage
