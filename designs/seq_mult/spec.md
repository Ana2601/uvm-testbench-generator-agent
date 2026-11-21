# seq_mult: sequential multiplier with start/busy/done

Unsigned `W = 16`-bit multiplier. It takes exactly W cycles per product.

| Port | Dir | Width | Meaning |
|---|---|---|---|
| `clk`, `rst_n` | in | 1 | clock, asynchronous active-low reset |
| `start` | in | 1 | begin a multiplication of `a` and `b` (only when not busy) |
| `a`, `b` | in | W | unsigned operands, sampled in the start cycle |
| `busy` | out | 1 | a multiplication is in progress |
| `done` | out | 1 | one-cycle pulse: `p` has just been updated with a new product |
| `p` | out | 2W | the most recent product. Holds its value until the next `done` |

Behaviour:

- After reset: `busy = 0`, `done = 0`, `p = 0`.
- A start is accepted on a rising edge where `start && !busy`. `busy` is high from the
  next cycle for exactly W cycles.
- In the cycle after the last busy cycle, `busy = 0`, `done = 1` and `p = a * b` (the
  operands of the accepted start). A new start can be accepted in that cycle.
- `start` while busy is ignored. `a` and `b` may change freely after the start cycle.

Verification focus: operands 0, 1, max and powers of two; random operands; back-to-back
starts; `start` held high; `start` pulses while busy; reset while busy.
