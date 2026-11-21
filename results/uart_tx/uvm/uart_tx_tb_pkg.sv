`timescale 1ns/1ps
package uart_tx_tb_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    class uart_tx_item extends uvm_sequence_item;
        `uvm_object_utils(uart_tx_item)
        logic rst_n;
        logic tx_valid;
        logic [7:0] tx_data;
        logic tx_ready;
        logic txd;
        function new(string name = "uart_tx_item"); super.new(name); endfunction
        function string convert2string(); return $sformatf("rst_n=%0h tx_valid=%0h tx_data=%0h tx_ready=%0h txd=%0h", rst_n, tx_valid, tx_data, tx_ready, txd); endfunction
    endclass

    class uart_tx_reset_seq extends uvm_sequence #(uart_tx_item);
        `uvm_object_utils(uart_tx_reset_seq)
        function new(string name = "uart_tx_reset_seq"); super.new(name); endfunction
        task body();
            repeat (3) begin
                uart_tx_item t = uart_tx_item::type_id::create("t");
                start_item(t);
                t.tx_valid = 1'b0;
                t.tx_data = 8'h00;
                t.rst_n = 1'b0;
                finish_item(t);
            end
        endtask
    endclass

    class uart_tx_random_frames_seq extends uvm_sequence #(uart_tx_item);
        `uvm_object_utils(uart_tx_random_frames_seq)
        int i;
        function new(string name = "uart_tx_random_frames_seq"); super.new(name); endfunction
        task body();
            for (i = 0; i < 4000; i++) begin
                uart_tx_item t = uart_tx_item::type_id::create("t");
                start_item(t);
                t.tx_valid = 1'b0;
                t.tx_data = 8'h00;
                t.tx_valid = 1'($urandom_range(0, 3) == 0);
                t.tx_data = 8'($urandom);
                t.rst_n = 1'b1;
                finish_item(t);
            end
        endtask
    endclass

    class uart_tx_patterns_back_to_back_seq extends uvm_sequence #(uart_tx_item);
        `uvm_object_utils(uart_tx_patterns_back_to_back_seq)
        int i;
        function new(string name = "uart_tx_patterns_back_to_back_seq"); super.new(name); endfunction
        task body();
            for (i = 0; i < 328; i++) begin
                uart_tx_item t = uart_tx_item::type_id::create("t");
                start_item(t);
                t.tx_valid = 1'b0;
                t.tx_data = 8'h00;
                t.tx_valid = 1'b1;
                t.tx_data = ((i / 41) % 4 == 0) ? 8'h00 : ((i / 41) % 4 == 1) ? 8'hFF : ((i / 41) % 4 == 2) ? 8'h55 : 8'hAA;
                t.rst_n = 1'b1;
                finish_item(t);
            end
        endtask
    endclass

    class uart_tx_reset_mid_frame_seq extends uvm_sequence #(uart_tx_item);
        `uvm_object_utils(uart_tx_reset_mid_frame_seq)
        int i;
        function new(string name = "uart_tx_reset_mid_frame_seq"); super.new(name); endfunction
        task body();
            for (i = 0; i < 300; i++) begin
                uart_tx_item t = uart_tx_item::type_id::create("t");
                start_item(t);
                t.tx_valid = 1'b0;
                t.tx_data = 8'h00;
                t.tx_valid = 1'($urandom_range(0, 1));
                t.tx_data = 8'($urandom);
                t.rst_n = ((i % 100) == 17 || (i % 100) == 18) ? 1'b0 : 1'b1;
                finish_item(t);
            end
        endtask
    endclass

    class uart_tx_driver extends uvm_driver #(uart_tx_item);
        `uvm_component_utils(uart_tx_driver)
        virtual uart_tx_if vif;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            if (!uvm_config_db #(virtual uart_tx_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "virtual interface not set")
        endfunction
        task run_phase(uvm_phase phase);
            forever begin
                seq_item_port.get_next_item(req);
                @(negedge vif.clk);
                vif.rst_n = req.rst_n;
                vif.tx_valid = req.tx_valid;
                vif.tx_data = req.tx_data;
                seq_item_port.item_done();
            end
        endtask
    endclass

    class uart_tx_monitor extends uvm_monitor;
        `uvm_component_utils(uart_tx_monitor)
        virtual uart_tx_if vif;
        uvm_analysis_port #(uart_tx_item) ap;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            ap = new("ap", this);
            if (!uvm_config_db #(virtual uart_tx_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "virtual interface not set")
        endfunction
        task run_phase(uvm_phase phase);
            forever begin
                uart_tx_item t;
                @(negedge vif.clk);
                #1;
                t = uart_tx_item::type_id::create("t");
                t.rst_n = vif.rst_n;
                t.tx_valid = vif.tx_valid;
                t.tx_data = vif.tx_data;
                t.tx_ready = vif.tx_ready;
                t.txd = vif.txd;
                ap.write(t);
            end
        endtask
    endclass

    class uart_tx_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(uart_tx_scoreboard)
        uvm_analysis_imp #(uart_tx_item, uart_tx_scoreboard) imp;
        // port mirrors: the plan's model and coverage code refer to ports by name
        logic rst_n;
        logic tx_valid;
        logic [7:0] tx_data;
        logic tx_ready;
        logic txd;
        logic exp_tx_ready;
        bit   chk_tx_ready;
        logic exp_txd;
        bit   chk_txd;
        int errors = 0, checks = 0;
        int cov_hits [8];
        // ---- reference model (from the plan) ----
        localparam int C = 4;
        bit m_busy;
        int m_cnt;          // cycles since the frame started (0 = first start-bit cycle)
        logic [7:0] m_data;
        bit m_just_done;    // the previous cycle was the last stop-bit cycle
        bit m_busy_at_reset;
        int m_bit;
        function void m_reset();
            m_busy_at_reset = m_busy;
            m_busy = 0;
            m_cnt = 0;
            m_data = 8'h00;
            m_just_done = 0;
        endfunction
        function void m_outputs();
            chk_tx_ready = 1'b1;
            chk_txd = 1'b1;
            exp_tx_ready = !m_busy;
            if (!m_busy) begin
                exp_txd = 1'b1;
            end else begin
                m_bit = m_cnt / C;                 // 0 start, 1..8 data, 9 stop
                if (m_bit == 0)      exp_txd = 1'b0;
                else if (m_bit <= 8) exp_txd = m_data[m_bit - 1];
                else                 exp_txd = 1'b1;
            end
        endfunction
        function void m_step();
            m_just_done = 0;
            if (!m_busy) begin
                if (tx_valid) begin
                    m_busy = 1;
                    m_cnt  = 0;
                    m_data = tx_data;
                end
            end else begin
                m_cnt = m_cnt + 1;
                if (m_cnt == 10 * C) begin
                    m_busy = 0;
                    m_just_done = 1;
                end
            end
        endfunction
        function new(string name, uvm_component parent);
            super.new(name, parent);
            imp = new("imp", this);
        endfunction
        function void write(uart_tx_item t);
            rst_n = t.rst_n;
            tx_valid = t.tx_valid;
            tx_data = t.tx_data;
            tx_ready = t.tx_ready;
            txd = t.txd;
            if (rst_n == 1'b0) m_reset();
            m_outputs();
            checks++;
            if (chk_tx_ready && (tx_ready !== exp_tx_ready)) begin
                errors++;
                if (errors <= 12)
                    `uvm_error("SCB", $sformatf("MISMATCH cycle=%0d port=tx_ready got=%0h exp=%0h | %s", checks, tx_ready, exp_tx_ready, t.convert2string()))
            end
            if (chk_txd && (txd !== exp_txd)) begin
                errors++;
                if (errors <= 12)
                    `uvm_error("SCB", $sformatf("MISMATCH cycle=%0d port=txd got=%0h exp=%0h | %s", checks, txd, exp_txd, t.convert2string()))
            end
            if (tx_valid && tx_ready) cov_hits[0]++;
            if (tx_valid && tx_ready && tx_data == 8'h00) cov_hits[1]++;
            if (tx_valid && tx_ready && tx_data == 8'hFF) cov_hits[2]++;
            if (tx_valid && tx_ready && tx_data == 8'h55) cov_hits[3]++;
            if (tx_valid && tx_ready && tx_data == 8'hAA) cov_hits[4]++;
            if (tx_valid && !tx_ready) cov_hits[5]++;
            if (tx_valid && tx_ready && m_just_done) cov_hits[6]++;
            if (rst_n == 1'b0 && m_busy_at_reset) cov_hits[7]++;
            if (rst_n != 1'b0) m_step();
        endfunction
        function void report_phase(uvm_phase phase);
            $display("COVER frame_accepted %0d", cov_hits[0]);
            $display("COVER data_0x00 %0d", cov_hits[1]);
            $display("COVER data_0xff %0d", cov_hits[2]);
            $display("COVER data_0x55 %0d", cov_hits[3]);
            $display("COVER data_0xaa %0d", cov_hits[4]);
            $display("COVER request_while_busy %0d", cov_hits[5]);
            $display("COVER back_to_back %0d", cov_hits[6]);
            $display("COVER reset_mid_frame %0d", cov_hits[7]);
            $display("CHECKS %0d ERRORS %0d", checks, errors);
            if (errors == 0) $display("PASS"); else $display("FAIL");
        endfunction
    endclass

    class uart_tx_agent extends uvm_agent;
        `uvm_component_utils(uart_tx_agent)
        uvm_sequencer #(uart_tx_item) sqr;
        uart_tx_driver  drv;
        uart_tx_monitor mon;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            sqr = uvm_sequencer #(uart_tx_item)::type_id::create("sqr", this);
            drv = uart_tx_driver::type_id::create("drv", this);
            mon = uart_tx_monitor::type_id::create("mon", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass

    class uart_tx_env extends uvm_env;
        `uvm_component_utils(uart_tx_env)
        uart_tx_agent      agt;
        uart_tx_scoreboard scb;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            agt = uart_tx_agent::type_id::create("agt", this);
            scb = uart_tx_scoreboard::type_id::create("scb", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            agt.mon.ap.connect(scb.imp);
        endfunction
    endclass

    class uart_tx_test extends uvm_test;
        `uvm_component_utils(uart_tx_test)
        uart_tx_env env;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            env = uart_tx_env::type_id::create("env", this);
        endfunction
        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            begin uart_tx_reset_seq s = uart_tx_reset_seq::type_id::create("s"); s.start(env.agt.sqr); end
            begin uart_tx_random_frames_seq s = uart_tx_random_frames_seq::type_id::create("s"); s.start(env.agt.sqr); end
            begin uart_tx_patterns_back_to_back_seq s = uart_tx_patterns_back_to_back_seq::type_id::create("s"); s.start(env.agt.sqr); end
            begin uart_tx_reset_mid_frame_seq s = uart_tx_reset_mid_frame_seq::type_id::create("s"); s.start(env.agt.sqr); end
            #20;
            phase.drop_objection(this);
        endtask
    endclass
endpackage
