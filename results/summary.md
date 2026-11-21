| Design | Runs | Final status | Checks | Coverage | Mutants killed | Equivalent / stillborn | UVM on Verilator | DUT bugs reported |
|---|---:|---|---:|---:|---:|---|---|---|
| `apb_regs` | 2 | PASS | 7400 | 100.0 % | **30/30 (100.0 %)** | 1 / 0 | PASS (7404 checks, 100.0 % cov) | 0 |
| `seq_mult` | 2 | PASS | 6608 | 100.0 % | **19/19 (100.0 %)** | 4 / 0 | PASS (6612 checks, 100.0 % cov) | 0 |
| `sync_fifo` | 2 | PASS | 3000 | 100.0 % | **18/18 (100.0 %)** | 0 / 0 | PASS (3004 checks, 100.0 % cov) | 0 |
| `uart_tx` | 2 | PASS | 4628 | 100.0 % | **20/20 (100.0 %)** | 3 / 0 | PASS (4632 checks, 100.0 % cov) | 0 |
| `uart_tx_buggy` | 1 | FAIL | 4628 | 100.0 % | - | - | FAIL (4632 checks, 100.0 % cov) | 1 |

### apb_regs

| Run | Status | Errors | Coverage | Mutation score | Change |
|---:|---|---:|---:|---:|---|
| 1 | PASS | 0 | 72.7 | 93.3 % | Register model with RO/W1C semantics; random transfers to the mapped addresses. |
| 2 | PASS | 0 | 100.0 | 100.0 % | All 16 addresses with idle cycles; write / reset / read-back-all sequence. |

Agent summary: Checks prdata (where defined), pslverr and pready every cycle against a register model with RW, RO and W1C semantics. Covers every register read and write, both error kinds, idle cycles and reset-after-traffic. The read-back-after-reset sequence was what caught wrong reset values.

### seq_mult

| Run | Status | Errors | Coverage | Mutation score | Change |
|---:|---|---:|---:|---:|---|
| 1 | PASS | 0 | 37.5 | 94.7 % | Latency-exact handshake model; random starts and operands. |
| 2 | PASS | 0 | 100.0 | 100.0 % | Corner operands (0, 1, max, powers of two) with start held high; resets while busy. |

Agent summary: Exact-latency model of the start/busy/done protocol and the product; corner operands, back-to-back starts, start while busy and reset while busy are all covered and checked.

### sync_fifo

| Run | Status | Errors | Coverage | Mutation score | Change |
|---:|---|---:|---:|---:|---|
| 1 | FAIL | 1657 | 100.0 | - | First plan: circular-buffer model, random traffic, boundary coverage. |
| 2 | PASS | 0 | 100.0 | 100.0 % | Model fix: push/pop decided on the state before the edge (spec: no bypass when full). |

Agent summary: Reference model of a FWFT FIFO (spec-level: circular buffer, count, no-bypass rule), random back-pressure on both sides, 7 boundary coverage points (including simultaneous read/write at 1, 7 and full). The first plan's model was wrong (it allowed a bypass write); the spec decided it, and the DUT was right.

### uart_tx

| Run | Status | Errors | Coverage | Mutation score | Change |
|---:|---|---:|---:|---:|---|
| 1 | PASS | 0 | 37.5 | 95.0 % | Cycle-counting frame model; random requests. |
| 2 | PASS | 0 | 100.0 | 100.0 % | Directed: 4 data patterns back-to-back with tx_valid held high; mid-frame resets. |

Agent summary: Frame-level reference model checks txd and tx_ready every cycle, including during reset. Random plus directed stimulus: patterns 0x00/0xFF/0x55/0xAA, back-to-back frames, requests while busy, and resets mid-frame. The mid-frame reset sequence was needed to catch a wrong txd reset value.

### uart_tx_buggy

| Run | Status | Errors | Coverage | Mutation score | Change |
|---:|---|---:|---:|---:|---|
| 1 | FAIL | 2572 | 100.0 | - | Plan from the uart_tx spec, unchanged apart from the DUT name. |

**DUT bug reported:** Stop bit is one clock short (CLKS_PER_BIT-1 cycles); tx_ready rises a cycle early

- spec: Each bit lasts exactly CLKS_PER_BIT cycles ... tx_ready rises again in the first cycle after the stop bit.
- evidence: First mismatch at cycle 42: tx_ready=1, expected 0 (frame accepted 40 cycles earlier; start and data bits match, the stop bit lasts 3 clocks instead of 4). On back-to-back frames the next start bit begins one cycle early (txd=0, expected 1 at cycle 43).

Agent summary: Found a DUT bug: the stop bit is CLKS_PER_BIT-1 clocks. The reference model was kept faithful to the spec; it fails on this DUT and passes on the correct uart_tx.
