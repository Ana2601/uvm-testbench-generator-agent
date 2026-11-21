"""Emit a UVM (IEEE 1800.2) testbench from the same verification plan.

    tb_top ── <dut>_if ── DUT
      └─ run_test("<dut>_test")
           <dut>_env
             ├─ <dut>_agent: sequencer → driver (drives at negedge) ; monitor (samples at negedge+1)
             └─ <dut>_scoreboard: reference model (plan.model, verbatim) + compare + coverage

The reference-model code and the stimulus code are the same SystemVerilog the
Icarus testbench runs, so both flavours check exactly the same thing. Runs on any
UVM simulator; `make uvm` runs it on Verilator 5 against Accellera uvm-core.
"""
from __future__ import annotations

from .plan import driven_inputs, outputs


def _w(width: int) -> str:
    return f"[{width - 1}:0] " if width > 1 else ""


def _ind(code: str, n: int) -> str:
    pad = " " * n
    return "\n".join(pad + l if l.strip() else "" for l in code.strip().splitlines())


def emit(plan: dict, ports: dict) -> dict[str, str]:
    d = plan["dut"]
    clk, rst = plan["clock"], plan["reset"]["port"]
    act = plan["reset"]["active"]
    ins, outs = driven_inputs(plan, ports), outputs(ports)
    sigs = [rst] + ins + outs
    defaults = plan.get("defaults", {})
    period = plan.get("period_ns", 10)
    files = {}

    # ---------------------------------------------------------------- interface
    L = ["`timescale 1ns/1ps", f"interface {d}_if (input logic {clk});"]
    for n in sigs:
        L.append(f"    logic {_w(ports[n][1])}{n};")
    L.append("endinterface")
    files[f"{d}_if.sv"] = "\n".join(L) + "\n"

    # ---------------------------------------------------------------- package
    P = ["`timescale 1ns/1ps", f"package {d}_tb_pkg;", "    import uvm_pkg::*;", "    `include \"uvm_macros.svh\"", ""]

    # sequence item
    P.append(f"    class {d}_item extends uvm_sequence_item;")
    P.append(f"        `uvm_object_utils({d}_item)")
    for n in sigs:
        P.append(f"        logic {_w(ports[n][1])}{n};")
    P.append(f'        function new(string name = "{d}_item"); super.new(name); endfunction')
    fmt = " ".join(f"{n}=%0h" for n in sigs)
    P.append(f'        function string convert2string(); return $sformatf("{fmt}", {", ".join(sigs)}); endfunction')
    P.append("    endclass\n")

    # sequences
    P.append(f"    class {d}_reset_seq extends uvm_sequence #({d}_item);")
    P.append(f"        `uvm_object_utils({d}_reset_seq)")
    P.append(f'        function new(string name = "{d}_reset_seq"); super.new(name); endfunction')
    P.append("        task body();")
    P.append(f"            repeat ({plan['reset'].get('cycles', 3)}) begin")
    P.append(f'                {d}_item t = {d}_item::type_id::create("t");')
    P.append("                start_item(t);")
    for n in ins:
        P.append(f"                t.{n} = {defaults.get(n, '0')};")
    P.append(f"                t.{rst} = 1'b{act};")
    P.append("                finish_item(t);")
    P.append("            end")
    P.append("        endtask")
    P.append("    endclass\n")
    for s in plan["sequences"]:
        cls = f"{d}_{s['name']}_seq"
        P.append(f"    class {cls} extends uvm_sequence #({d}_item);")
        P.append(f"        `uvm_object_utils({cls})")
        P.append("        int i;")
        if plan.get("seq_vars"):
            P.append(_ind(plan["seq_vars"], 8))
        P.append(f'        function new(string name = "{cls}"); super.new(name); endfunction')
        P.append("        task body();")
        P.append(f"            for (i = 0; i < {s['cycles']}; i++) begin")
        P.append(f'                {d}_item t = {d}_item::type_id::create("t");')
        P.append("                start_item(t);")
        for n in ins:
            P.append(f"                t.{n} = {defaults.get(n, '0')};")
        if s.get("pre"):
            P.append(_ind(s["pre"], 16))
        for n, e in s.get("drive", {}).items():
            P.append(f"                t.{n} = {e};")
        rw = s.get("reset_when")
        P.append(f"                t.{rst} = ({rw}) ? 1'b{act} : 1'b{1 - act};" if rw
                 else f"                t.{rst} = 1'b{1 - act};")
        P.append("                finish_item(t);")
        P.append("            end")
        P.append("        endtask")
        P.append("    endclass\n")

    # driver
    P.append(f"    class {d}_driver extends uvm_driver #({d}_item);")
    P.append(f"        `uvm_component_utils({d}_driver)")
    P.append(f"        virtual {d}_if vif;")
    P.append("        function new(string name, uvm_component parent); super.new(name, parent); endfunction")
    P.append("        function void build_phase(uvm_phase phase);")
    P.append(f'            if (!uvm_config_db #(virtual {d}_if)::get(this, "", "vif", vif))')
    P.append('                `uvm_fatal("NOVIF", "virtual interface not set")')
    P.append("        endfunction")
    P.append("        task run_phase(uvm_phase phase);")
    P.append("            forever begin")
    P.append("                seq_item_port.get_next_item(req);")
    P.append(f"                @(negedge vif.{clk});")
    for n in [rst] + ins:
        P.append(f"                vif.{n} = req.{n};")
    P.append("                seq_item_port.item_done();")
    P.append("            end")
    P.append("        endtask")
    P.append("    endclass\n")

    # monitor
    P.append(f"    class {d}_monitor extends uvm_monitor;")
    P.append(f"        `uvm_component_utils({d}_monitor)")
    P.append(f"        virtual {d}_if vif;")
    P.append(f"        uvm_analysis_port #({d}_item) ap;")
    P.append("        function new(string name, uvm_component parent); super.new(name, parent); endfunction")
    P.append("        function void build_phase(uvm_phase phase);")
    P.append('            ap = new("ap", this);')
    P.append(f'            if (!uvm_config_db #(virtual {d}_if)::get(this, "", "vif", vif))')
    P.append('                `uvm_fatal("NOVIF", "virtual interface not set")')
    P.append("        endfunction")
    P.append("        task run_phase(uvm_phase phase);")
    P.append("            forever begin")
    P.append(f"                {d}_item t;")
    P.append(f"                @(negedge vif.{clk});")
    P.append("                #1;")
    P.append(f'                t = {d}_item::type_id::create("t");')
    for n in sigs:
        P.append(f"                t.{n} = vif.{n};")
    P.append("                ap.write(t);")
    P.append("            end")
    P.append("        endtask")
    P.append("    endclass\n")

    # scoreboard (reference model + compare + coverage)
    cov = plan["coverage"]
    P.append(f"    class {d}_scoreboard extends uvm_scoreboard;")
    P.append(f"        `uvm_component_utils({d}_scoreboard)")
    P.append(f"        uvm_analysis_imp #({d}_item, {d}_scoreboard) imp;")
    P.append("        // port mirrors: the plan's model and coverage code refer to ports by name")
    for n in sigs:
        P.append(f"        logic {_w(ports[n][1])}{n};")
    for n in outs:
        P.append(f"        logic {_w(ports[n][1])}exp_{n};")
        P.append(f"        bit   chk_{n};")
    P.append("        int errors = 0, checks = 0;")
    P.append(f"        int cov_hits [{max(len(cov), 1)}];")
    P.append("        // ---- reference model (from the plan) ----")
    P.append(_ind(plan["model"]["decls"], 8))
    P.append("        function void m_reset();\n" + _ind(plan["model"]["reset"], 12) + "\n        endfunction")
    P.append("        function void m_outputs();\n"
             + "\n".join(f"            chk_{n} = 1'b1;" for n in outs) + "\n"
             + _ind(plan["model"]["outputs"], 12) + "\n        endfunction")
    P.append("        function void m_step();\n" + _ind(plan["model"]["step"], 12) + "\n        endfunction")
    P.append("        function new(string name, uvm_component parent);")
    P.append("            super.new(name, parent);")
    P.append('            imp = new("imp", this);')
    P.append("        endfunction")
    P.append(f"        function void write({d}_item t);")
    for n in sigs:
        P.append(f"            {n} = t.{n};")
    P.append(f"            if ({rst} == 1'b{act}) m_reset();")
    P.append("            m_outputs();")
    P.append("            checks++;")
    for n in outs:
        P.append(f"            if (chk_{n} && ({n} !== exp_{n})) begin")
        P.append("                errors++;")
        P.append("                if (errors <= 12)")
        P.append(f'                    `uvm_error("SCB", $sformatf("MISMATCH cycle=%0d port={n} got=%0h exp=%0h | %s",'
                 f" checks, {n}, exp_{n}, t.convert2string()))")
        P.append("            end")
    for k, c in enumerate(cov):
        P.append(f"            if ({c['expr']}) cov_hits[{k}]++;")
    P.append(f"            if ({rst} != 1'b{act}) m_step();")
    P.append("        endfunction")
    P.append("        function void report_phase(uvm_phase phase);")
    for k, c in enumerate(cov):
        P.append(f'            $display("COVER {c["name"]} %0d", cov_hits[{k}]);')
    P.append('            $display("CHECKS %0d ERRORS %0d", checks, errors);')
    P.append('            if (errors == 0) $display("PASS"); else $display("FAIL");')
    P.append("        endfunction")
    P.append("    endclass\n")

    # agent, env, test
    P.append(f"""    class {d}_agent extends uvm_agent;
        `uvm_component_utils({d}_agent)
        uvm_sequencer #({d}_item) sqr;
        {d}_driver  drv;
        {d}_monitor mon;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            sqr = uvm_sequencer #({d}_item)::type_id::create("sqr", this);
            drv = {d}_driver::type_id::create("drv", this);
            mon = {d}_monitor::type_id::create("mon", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass

    class {d}_env extends uvm_env;
        `uvm_component_utils({d}_env)
        {d}_agent      agt;
        {d}_scoreboard scb;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            agt = {d}_agent::type_id::create("agt", this);
            scb = {d}_scoreboard::type_id::create("scb", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            agt.mon.ap.connect(scb.imp);
        endfunction
    endclass

    class {d}_test extends uvm_test;
        `uvm_component_utils({d}_test)
        {d}_env env;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            env = {d}_env::type_id::create("env", this);
        endfunction
        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            begin {d}_reset_seq s = {d}_reset_seq::type_id::create("s"); s.start(env.agt.sqr); end""")
    for s in plan["sequences"]:
        cls = f"{d}_{s['name']}_seq"
        P.append(f'            begin {cls} s = {cls}::type_id::create("s"); s.start(env.agt.sqr); end')
    P.append(f"""            #{period * 2};
            phase.drop_objection(this);
        endtask
    endclass
endpackage""")
    files[f"{d}_tb_pkg.sv"] = "\n".join(P) + "\n"

    # ---------------------------------------------------------------- top
    params = plan.get("params", {})
    pstr = (" #(" + ", ".join(f".{k}({v})" for k, v in params.items()) + ")") if params else ""
    conns = ", ".join([f".{clk}({clk})"] + [f".{n}(ifc.{n})" for n in sigs])
    files["tb_top.sv"] = f"""`timescale 1ns/1ps
module tb_top;
    import uvm_pkg::*;
    import {d}_tb_pkg::*;
    logic {clk} = 1'b0;
    always #{period / 2} {clk} = ~{clk};
    {d}_if ifc ({clk});
    initial ifc.{rst} = 1'b{act};
    {d}{pstr} dut ({conns});
    initial begin
        uvm_config_db #(virtual {d}_if)::set(null, "*", "vif", ifc);
        run_test("{d}_test");
    end
endmodule
"""
    return files


def file_order(d: str) -> list[str]:
    return [f"{d}_if.sv", f"{d}_tb_pkg.sv", "tb_top.sv"]
