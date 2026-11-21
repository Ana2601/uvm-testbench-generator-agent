`timescale 1ns/1ps
package sync_fifo_tb_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    class sync_fifo_item extends uvm_sequence_item;
        `uvm_object_utils(sync_fifo_item)
        logic rst_n;
        logic wr_valid;
        logic [7:0] wr_data;
        logic rd_ready;
        logic wr_ready;
        logic rd_valid;
        logic [7:0] rd_data;
        logic [3:0] count;
        function new(string name = "sync_fifo_item"); super.new(name); endfunction
        function string convert2string(); return $sformatf("rst_n=%0h wr_valid=%0h wr_data=%0h rd_ready=%0h wr_ready=%0h rd_valid=%0h rd_data=%0h count=%0h", rst_n, wr_valid, wr_data, rd_ready, wr_ready, rd_valid, rd_data, count); endfunction
    endclass

    class sync_fifo_reset_seq extends uvm_sequence #(sync_fifo_item);
        `uvm_object_utils(sync_fifo_reset_seq)
        function new(string name = "sync_fifo_reset_seq"); super.new(name); endfunction
        task body();
            repeat (3) begin
                sync_fifo_item t = sync_fifo_item::type_id::create("t");
                start_item(t);
                t.wr_valid = 1'b0;
                t.wr_data = 8'h00;
                t.rd_ready = 1'b0;
                t.rst_n = 1'b0;
                finish_item(t);
            end
        endtask
    endclass

    class sync_fifo_random_traffic_seq extends uvm_sequence #(sync_fifo_item);
        `uvm_object_utils(sync_fifo_random_traffic_seq)
        int i;
        function new(string name = "sync_fifo_random_traffic_seq"); super.new(name); endfunction
        task body();
            for (i = 0; i < 3000; i++) begin
                sync_fifo_item t = sync_fifo_item::type_id::create("t");
                start_item(t);
                t.wr_valid = 1'b0;
                t.wr_data = 8'h00;
                t.rd_ready = 1'b0;
                t.wr_valid = 1'($urandom_range(0, 1));
                t.wr_data = 8'($urandom);
                t.rd_ready = 1'($urandom_range(0, 1));
                t.rst_n = 1'b1;
                finish_item(t);
            end
        endtask
    endclass

    class sync_fifo_driver extends uvm_driver #(sync_fifo_item);
        `uvm_component_utils(sync_fifo_driver)
        virtual sync_fifo_if vif;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            if (!uvm_config_db #(virtual sync_fifo_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "virtual interface not set")
        endfunction
        task run_phase(uvm_phase phase);
            forever begin
                seq_item_port.get_next_item(req);
                @(negedge vif.clk);
                vif.rst_n = req.rst_n;
                vif.wr_valid = req.wr_valid;
                vif.wr_data = req.wr_data;
                vif.rd_ready = req.rd_ready;
                seq_item_port.item_done();
            end
        endtask
    endclass

    class sync_fifo_monitor extends uvm_monitor;
        `uvm_component_utils(sync_fifo_monitor)
        virtual sync_fifo_if vif;
        uvm_analysis_port #(sync_fifo_item) ap;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            ap = new("ap", this);
            if (!uvm_config_db #(virtual sync_fifo_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "virtual interface not set")
        endfunction
        task run_phase(uvm_phase phase);
            forever begin
                sync_fifo_item t;
                @(negedge vif.clk);
                #1;
                t = sync_fifo_item::type_id::create("t");
                t.rst_n = vif.rst_n;
                t.wr_valid = vif.wr_valid;
                t.wr_data = vif.wr_data;
                t.rd_ready = vif.rd_ready;
                t.wr_ready = vif.wr_ready;
                t.rd_valid = vif.rd_valid;
                t.rd_data = vif.rd_data;
                t.count = vif.count;
                ap.write(t);
            end
        endtask
    endclass

    class sync_fifo_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(sync_fifo_scoreboard)
        uvm_analysis_imp #(sync_fifo_item, sync_fifo_scoreboard) imp;
        // port mirrors: the plan's model and coverage code refer to ports by name
        logic rst_n;
        logic wr_valid;
        logic [7:0] wr_data;
        logic rd_ready;
        logic wr_ready;
        logic rd_valid;
        logic [7:0] rd_data;
        logic [3:0] count;
        logic exp_wr_ready;
        bit   chk_wr_ready;
        logic exp_rd_valid;
        bit   chk_rd_valid;
        logic [7:0] exp_rd_data;
        bit   chk_rd_data;
        logic [3:0] exp_count;
        bit   chk_count;
        int errors = 0, checks = 0;
        int cov_hits [7];
        // ---- reference model (from the plan) ----
        logic [7:0] m_q [8];
        int m_head;
        int m_count;
        bit m_push, m_pop;
        function void m_reset();
            m_head = 0;
            m_count = 0;
        endfunction
        function void m_outputs();
            chk_wr_ready = 1'b1;
            chk_rd_valid = 1'b1;
            chk_rd_data = 1'b1;
            chk_count = 1'b1;
            exp_wr_ready = (m_count != 8);
            exp_rd_valid = (m_count != 0);
            exp_rd_data  = m_q[m_head];
            chk_rd_data  = (m_count != 0);
            exp_count    = 4'(m_count);
        endfunction
        function void m_step();
            // decide both handshakes on the state BEFORE the edge: a full FIFO refuses
            // a write even when a read happens in the same cycle (spec: no bypass)
            m_push = wr_valid && (m_count != 8);
            m_pop  = rd_ready && (m_count != 0);
            if (m_push) m_q[(m_head + m_count) % 8] = wr_data;
            if (m_pop)  m_head = (m_head + 1) % 8;
            m_count = m_count + int'(m_push) - int'(m_pop);
        endfunction
        function new(string name, uvm_component parent);
            super.new(name, parent);
            imp = new("imp", this);
        endfunction
        function void write(sync_fifo_item t);
            rst_n = t.rst_n;
            wr_valid = t.wr_valid;
            wr_data = t.wr_data;
            rd_ready = t.rd_ready;
            wr_ready = t.wr_ready;
            rd_valid = t.rd_valid;
            rd_data = t.rd_data;
            count = t.count;
            if (rst_n == 1'b0) m_reset();
            m_outputs();
            checks++;
            if (chk_wr_ready && (wr_ready !== exp_wr_ready)) begin
                errors++;
                if (errors <= 12)
                    `uvm_error("SCB", $sformatf("MISMATCH cycle=%0d port=wr_ready got=%0h exp=%0h | %s", checks, wr_ready, exp_wr_ready, t.convert2string()))
            end
            if (chk_rd_valid && (rd_valid !== exp_rd_valid)) begin
                errors++;
                if (errors <= 12)
                    `uvm_error("SCB", $sformatf("MISMATCH cycle=%0d port=rd_valid got=%0h exp=%0h | %s", checks, rd_valid, exp_rd_valid, t.convert2string()))
            end
            if (chk_rd_data && (rd_data !== exp_rd_data)) begin
                errors++;
                if (errors <= 12)
                    `uvm_error("SCB", $sformatf("MISMATCH cycle=%0d port=rd_data got=%0h exp=%0h | %s", checks, rd_data, exp_rd_data, t.convert2string()))
            end
            if (chk_count && (count !== exp_count)) begin
                errors++;
                if (errors <= 12)
                    `uvm_error("SCB", $sformatf("MISMATCH cycle=%0d port=count got=%0h exp=%0h | %s", checks, count, exp_count, t.convert2string()))
            end
            if (count == 0) cov_hits[0]++;
            if (count == 8) cov_hits[1]++;
            if (count == 8 && wr_valid) cov_hits[2]++;
            if (count == 0 && rd_ready) cov_hits[3]++;
            if (count == 1 && wr_valid && rd_ready) cov_hits[4]++;
            if (count == 7 && wr_valid && rd_ready) cov_hits[5]++;
            if (count == 8 && wr_valid && rd_ready) cov_hits[6]++;
            if (rst_n != 1'b0) m_step();
        endfunction
        function void report_phase(uvm_phase phase);
            $display("COVER empty %0d", cov_hits[0]);
            $display("COVER full %0d", cov_hits[1]);
            $display("COVER write_when_full %0d", cov_hits[2]);
            $display("COVER read_when_empty %0d", cov_hits[3]);
            $display("COVER simul_rw_at_1 %0d", cov_hits[4]);
            $display("COVER simul_rw_at_7 %0d", cov_hits[5]);
            $display("COVER simul_rw_when_full %0d", cov_hits[6]);
            $display("CHECKS %0d ERRORS %0d", checks, errors);
            if (errors == 0) $display("PASS"); else $display("FAIL");
        endfunction
    endclass

    class sync_fifo_agent extends uvm_agent;
        `uvm_component_utils(sync_fifo_agent)
        uvm_sequencer #(sync_fifo_item) sqr;
        sync_fifo_driver  drv;
        sync_fifo_monitor mon;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            sqr = uvm_sequencer #(sync_fifo_item)::type_id::create("sqr", this);
            drv = sync_fifo_driver::type_id::create("drv", this);
            mon = sync_fifo_monitor::type_id::create("mon", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass

    class sync_fifo_env extends uvm_env;
        `uvm_component_utils(sync_fifo_env)
        sync_fifo_agent      agt;
        sync_fifo_scoreboard scb;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            agt = sync_fifo_agent::type_id::create("agt", this);
            scb = sync_fifo_scoreboard::type_id::create("scb", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            agt.mon.ap.connect(scb.imp);
        endfunction
    endclass

    class sync_fifo_test extends uvm_test;
        `uvm_component_utils(sync_fifo_test)
        sync_fifo_env env;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            env = sync_fifo_env::type_id::create("env", this);
        endfunction
        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            begin sync_fifo_reset_seq s = sync_fifo_reset_seq::type_id::create("s"); s.start(env.agt.sqr); end
            begin sync_fifo_random_traffic_seq s = sync_fifo_random_traffic_seq::type_id::create("s"); s.start(env.agt.sqr); end
            #20;
            phase.drop_objection(this);
        endtask
    endclass
endpackage
