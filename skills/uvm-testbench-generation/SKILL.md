---
name: uvm-testbench-generation
description: How to turn an RTL module and its spec into a verification plan (cycle-accurate reference model, stimulus sequences, functional coverage) that generates both an Icarus self-checking testbench and a UVM environment. Use when writing or repairing a plan for run_plan.
---

# Writing a verification plan

## 1. Read the spec as the contract

- List every **observable behaviour**: each output, in each state, on each cycle.
- Mark every **don't-care**. In the reference model, set `chk_<out> = 0` for those
  cycles (for example `chk_rd_data = (m_count != 0)` for a FIFO's data while empty).
  Checking a don't-care makes the testbench reject correct designs.
- Mark the **corner cases** the spec calls out (full, empty, back-to-back, error
  responses, reset in the middle of traffic). Each one becomes a coverage point and,
  usually, a directed sequence.

## 2. The reference model is cycle-based

The generated testbench calls your code in this order every cycle:

```
negedge  -> sequence `pre`, then `drive` the inputs (and reset)
+1 ns    -> if reset is active: model.reset
            model.outputs   (set exp_<out>, and chk_<out> = 0 where don't-care)
            compare every output with chk_<out> = 1; sample coverage
posedge  -> if reset is NOT active: model.step   (next-state update)
```

- `outputs` computes what the DUT shows **now**, from the model state and the current
  inputs. Registered outputs depend only on state. Combinational outputs, like
  `wr_ready = !full`, are a function of state, plus inputs if the spec says so.
- `step` computes the state after the rising edge. **Evaluate every handshake on the
  state *before* the edge**. Compute `push`/`pop`/`accept` first, then update.
  Updating the count and then testing it again is the most common model bug.
- Model the **spec, not the RTL**. Never copy the DUT's code into the model. A model
  that mirrors the RTL also mirrors its bugs.
- Use `exp_<out>` values in `step` when they encode a handshake the spec defines in
  terms of outputs (for example `tx_ready`).

## 3. Stimulus

- Start with **constrained-random traffic** that randomises every input independently,
  with a realistic bias (for example `rd_ready` high 75 % of the time).
- Add **directed sequences** for each corner the random run does not hit often:
  fill to full and keep writing, drain to empty and keep reading, back-to-back
  requests, requests while busy, illegal addresses, and reset in the middle of
  traffic (`reset_when`).
- A protocol with phases (APB setup/access, start/done) is driven with `seq_vars`
  holding the transfer, and `pre` advancing a small phase counter.

## 4. Coverage

- Each point is a boolean SystemVerilog expression, sampled on every checked cycle.
  Cover **states and transitions the spec cares about**: full and empty, both
  handshakes in the same cycle at each boundary, every register address, every
  error case, reset while busy.
- 100 % coverage is necessary but not sufficient. The mutation report shows what
  the checks themselves miss.

## 5. Reading the feedback

| Status | What to do |
|---|---|
| `PLAN_ERROR` | Fix the JSON or schema problem it names |
| `COMPILE_ERROR` | Your SystemVerilog does not compile on Icarus. Check the subset below |
| `FAIL` | Read the first mismatch: cycle, port, got vs expected, inputs. Re-derive the expected value **from the spec**. If the model was wrong, fix it. If the DUT is wrong, call `report_dut_bug`, quoting the spec clause, and keep the model as it is |
| `PASS` + holes | Add sequences that reach the uncovered points |
| `PASS` + survivors | Each survivor is a one-operator change in the DUT that your checks did not notice. Ask what stimulus would expose it (usually a corner you only reach rarely) and add a directed sequence. Survivors that are provably equivalent are already removed |

## 6. SystemVerilog subset (must compile on Icarus 12+ and Verilator 5)

- Model state and sequence variables: `logic [N:0]`, `bit`, `int`, fixed-size unpacked
  arrays (`logic [7:0] m_q [8];`). **No** queues, classes, `rand`/`constraint`,
  mailboxes, `fork`, delays or `$display`.
- Names: model state `m_*`, sequence variables `s_*`. Never redeclare a port name.
- Randomness: `$urandom`, `$urandom_range(lo, hi)`, cast to width, as in `8'($urandom)`.
- `drive` values and `pre` code may use `i` (cycle index within the sequence) and
  `s_*` variables only. They may not read DUT outputs.
- Width-cast integer arithmetic results that you assign to narrow signals
  (`exp_count = 4'(m_count);`).
