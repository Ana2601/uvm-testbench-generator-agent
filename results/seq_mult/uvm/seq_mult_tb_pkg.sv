`timescale 1ns/1ps
package seq_mult_tb_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    class seq_mult_item extends uvm_sequence_item;
        `uvm_object_utils(seq_mult_item)
        logic rst_n;
        logic start;
        logic [15:0] a;
        logic [15:0] b;
        logic busy;
        logic done;
        logic [31:0] p;
        function new(string name = "seq_mult_item"); super.new(name); endfunction
        function string convert2string(); return $sformatf("rst_n=%0h start=%0h a=%0h b=%0h busy=%0h done=%0h p=%0h", rst_n, start, a, b, busy, done, p); endfunction
    endclass

    class seq_mult_reset_seq extends uvm_sequence #(seq_mult_item);
        `uvm_object_utils(seq_mult_reset_seq)
        function new(string name = "seq_mult_reset_seq"); super.new(name); endfunction
        task body();
            repeat (3) begin
                seq_mult_item t = seq_mult_item::type_id::create("t");
                start_item(t);
                t.start = 1'b0;
                t.a = 16'h0;
                t.b = 16'h0;
                t.rst_n = 1'b0;
                finish_item(t);
            end
        endtask
    endclass

    class seq_mult_random_products_seq extends uvm_sequence #(seq_mult_item);
        `uvm_object_utils(seq_mult_random_products_seq)
        int i;
        logic [15:0] s_a, s_b;
        function new(string name = "seq_mult_random_products_seq"); super.new(name); endfunction
        task body();
            for (i = 0; i < 6000; i++) begin
                seq_mult_item t = seq_mult_item::type_id::create("t");
                start_item(t);
                t.start = 1'b0;
                t.a = 16'h0;
                t.b = 16'h0;
                t.start = 1'($urandom_range(0, 7) == 0);
                t.a = 16'($urandom);
                t.b = 16'($urandom);
                t.rst_n = 1'b1;
                finish_item(t);
            end
        endtask
    endclass

    class seq_mult_corner_operands_start_held_seq extends uvm_sequence #(seq_mult_item);
        `uvm_object_utils(seq_mult_corner_operands_start_held_seq)
        int i;
        logic [15:0] s_a, s_b;
        function new(string name = "seq_mult_corner_operands_start_held_seq"); super.new(name); endfunction
        task body();
            for (i = 0; i < 408; i++) begin
                seq_mult_item t = seq_mult_item::type_id::create("t");
                start_item(t);
                t.start = 1'b0;
                t.a = 16'h0;
                t.b = 16'h0;
                case ((i / 17) % 6)
                    0: begin s_a = 16'h0000; s_b = 16'($urandom); end
                    1: begin s_a = 16'($urandom); s_b = 16'h0000; end
                    2: begin s_a = 16'hFFFF; s_b = 16'hFFFF; end
                    3: begin s_a = 16'h0001; s_b = 16'($urandom); end
                    4: begin s_a = 16'h1 << ((i / 102) % 16); s_b = 16'hFFFF; end
                    default: begin s_a = 16'($urandom); s_b = 16'h1 << ((i / 17) % 16); end
                endcase
                t.start = 1'b1;
                t.a = s_a;
                t.b = s_b;
                t.rst_n = 1'b1;
                finish_item(t);
            end
        endtask
    endclass

    class seq_mult_reset_while_busy_seq extends uvm_sequence #(seq_mult_item);
        `uvm_object_utils(seq_mult_reset_while_busy_seq)
        int i;
        logic [15:0] s_a, s_b;
        function new(string name = "seq_mult_reset_while_busy_seq"); super.new(name); endfunction
        task body();
            for (i = 0; i < 200; i++) begin
                seq_mult_item t = seq_mult_item::type_id::create("t");
                start_item(t);
                t.start = 1'b0;
                t.a = 16'h0;
                t.b = 16'h0;
                t.start = 1'($urandom_range(0, 1));
                t.a = 16'($urandom);
                t.b = 16'($urandom);
                t.rst_n = ((i % 50) == 9) ? 1'b0 : 1'b1;
                finish_item(t);
            end
        endtask
    endclass

    class seq_mult_driver extends uvm_driver #(seq_mult_item);
        `uvm_component_utils(seq_mult_driver)
        virtual seq_mult_if vif;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            if (!uvm_config_db #(virtual seq_mult_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "virtual interface not set")
        endfunction
        task run_phase(uvm_phase phase);
            forever begin
                seq_item_port.get_next_item(req);
                @(negedge vif.clk);
                vif.rst_n = req.rst_n;
                vif.start = req.start;
                vif.a = req.a;
                vif.b = req.b;
                seq_item_port.item_done();
            end
        endtask
    endclass

    class seq_mult_monitor extends uvm_monitor;
        `uvm_component_utils(seq_mult_monitor)
        virtual seq_mult_if vif;
        uvm_analysis_port #(seq_mult_item) ap;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            ap = new("ap", this);
            if (!uvm_config_db #(virtual seq_mult_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "virtual interface not set")
        endfunction
        task run_phase(uvm_phase phase);
            forever begin
                seq_mult_item t;
                @(negedge vif.clk);
                #1;
                t = seq_mult_item::type_id::create("t");
                t.rst_n = vif.rst_n;
                t.start = vif.start;
                t.a = vif.a;
                t.b = vif.b;
                t.busy = vif.busy;
                t.done = vif.done;
                t.p = vif.p;
                ap.write(t);
            end
        endtask
    endclass

    class seq_mult_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(seq_mult_scoreboard)
        uvm_analysis_imp #(seq_mult_item, seq_mult_scoreboard) imp;
        // port mirrors: the plan's model and coverage code refer to ports by name
        logic rst_n;
        logic start;
        logic [15:0] a;
        logic [15:0] b;
        logic busy;
        logic done;
        logic [31:0] p;
        logic exp_busy;
        bit   chk_busy;
        logic exp_done;
        bit   chk_done;
        logic [31:0] exp_p;
        bit   chk_p;
        int errors = 0, checks = 0;
        int cov_hits [8];
        // ---- reference model (from the plan) ----
        localparam int W = 16;
        bit m_busy, m_done;
        int m_left;
        logic [15:0] m_a, m_b;
        logic [31:0] m_p;
        bit m_busy_at_reset;
        function void m_reset();
            m_busy_at_reset = m_busy;
            m_busy = 0;
            m_done = 0;
            m_left = 0;
            m_a = 16'h0;
            m_b = 16'h0;
            m_p = 32'h0;
        endfunction
        function void m_outputs();
            chk_busy = 1'b1;
            chk_done = 1'b1;
            chk_p = 1'b1;
            exp_busy = m_busy;
            exp_done = m_done;
            exp_p    = m_p;
        endfunction
        function void m_step();
            m_done = 0;
            if (!m_busy) begin
                if (start) begin
                    m_busy = 1;
                    m_left = W;
                    m_a = a;
                    m_b = b;
                end
            end else begin
                m_left = m_left - 1;
                if (m_left == 0) begin
                    m_busy = 0;
                    m_done = 1;
                    m_p = 32'(m_a) * 32'(m_b);
                end
            end
        endfunction
        function new(string name, uvm_component parent);
            super.new(name, parent);
            imp = new("imp", this);
        endfunction
        function void write(seq_mult_item t);
            rst_n = t.rst_n;
            start = t.start;
            a = t.a;
            b = t.b;
            busy = t.busy;
            done = t.done;
            p = t.p;
            if (rst_n == 1'b0) m_reset();
            m_outputs();
            checks++;
            if (chk_busy && (busy !== exp_busy)) begin
                errors++;
                if (errors <= 12)
                    `uvm_error("SCB", $sformatf("MISMATCH cycle=%0d port=busy got=%0h exp=%0h | %s", checks, busy, exp_busy, t.convert2string()))
            end
            if (chk_done && (done !== exp_done)) begin
                errors++;
                if (errors <= 12)
                    `uvm_error("SCB", $sformatf("MISMATCH cycle=%0d port=done got=%0h exp=%0h | %s", checks, done, exp_done, t.convert2string()))
            end
            if (chk_p && (p !== exp_p)) begin
                errors++;
                if (errors <= 12)
                    `uvm_error("SCB", $sformatf("MISMATCH cycle=%0d port=p got=%0h exp=%0h | %s", checks, p, exp_p, t.convert2string()))
            end
            if (start && !busy) cov_hits[0]++;
            if (start && busy) cov_hits[1]++;
            if (start && done) cov_hits[2]++;
            if (start && !busy && a == 16'h0) cov_hits[3]++;
            if (start && !busy && b == 16'h0) cov_hits[4]++;
            if (start && !busy && a == 16'hFFFF && b == 16'hFFFF) cov_hits[5]++;
            if (start && !busy && a != 16'h0 && (a & (a - 16'h1)) == 16'h0) cov_hits[6]++;
            if (!rst_n && m_busy_at_reset) cov_hits[7]++;
            if (rst_n != 1'b0) m_step();
        endfunction
        function void report_phase(uvm_phase phase);
            $display("COVER start_accepted %0d", cov_hits[0]);
            $display("COVER start_while_busy %0d", cov_hits[1]);
            $display("COVER back_to_back %0d", cov_hits[2]);
            $display("COVER a_zero %0d", cov_hits[3]);
            $display("COVER b_zero %0d", cov_hits[4]);
            $display("COVER both_max %0d", cov_hits[5]);
            $display("COVER a_power_of_two %0d", cov_hits[6]);
            $display("COVER reset_while_busy %0d", cov_hits[7]);
            $display("CHECKS %0d ERRORS %0d", checks, errors);
            if (errors == 0) $display("PASS"); else $display("FAIL");
        endfunction
    endclass

    class seq_mult_agent extends uvm_agent;
        `uvm_component_utils(seq_mult_agent)
        uvm_sequencer #(seq_mult_item) sqr;
        seq_mult_driver  drv;
        seq_mult_monitor mon;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            sqr = uvm_sequencer #(seq_mult_item)::type_id::create("sqr", this);
            drv = seq_mult_driver::type_id::create("drv", this);
            mon = seq_mult_monitor::type_id::create("mon", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass

    class seq_mult_env extends uvm_env;
        `uvm_component_utils(seq_mult_env)
        seq_mult_agent      agt;
        seq_mult_scoreboard scb;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            agt = seq_mult_agent::type_id::create("agt", this);
            scb = seq_mult_scoreboard::type_id::create("scb", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            agt.mon.ap.connect(scb.imp);
        endfunction
    endclass

    class seq_mult_test extends uvm_test;
        `uvm_component_utils(seq_mult_test)
        seq_mult_env env;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            env = seq_mult_env::type_id::create("env", this);
        endfunction
        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            begin seq_mult_reset_seq s = seq_mult_reset_seq::type_id::create("s"); s.start(env.agt.sqr); end
            begin seq_mult_random_products_seq s = seq_mult_random_products_seq::type_id::create("s"); s.start(env.agt.sqr); end
            begin seq_mult_corner_operands_start_held_seq s = seq_mult_corner_operands_start_held_seq::type_id::create("s"); s.start(env.agt.sqr); end
            begin seq_mult_reset_while_busy_seq s = seq_mult_reset_while_busy_seq::type_id::create("s"); s.start(env.agt.sqr); end
            #20;
            phase.drop_objection(this);
        endtask
    endclass
endpackage
