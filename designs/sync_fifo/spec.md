# sync_fifo: synchronous FIFO, valid/ready, first-word fall-through

Parameters: `W = 8` data bits, `DEPTH = 8` entries.

| Port | Dir | Width | Meaning |
|---|---|---|---|
| `clk` | in | 1 | clock, rising edge |
| `rst_n` | in | 1 | asynchronous active-low reset; empties the FIFO |
| `wr_valid` | in | 1 | writer offers `wr_data` |
| `wr_data` | in | W | write data |
| `wr_ready` | out | 1 | FIFO can accept a word: high exactly when it is not full |
| `rd_valid` | out | 1 | `rd_data` holds the oldest word: high exactly when it is not empty |
| `rd_data` | out | W | oldest word (first-word fall-through: visible as soon as it is stored) |
| `rd_ready` | in | 1 | reader takes the word this cycle |
| `count` | out | log2(DEPTH)+1 | number of stored words, 0 ... DEPTH |

Rules:

- A write happens on a rising edge where `wr_valid && wr_ready`; a read where `rd_valid && rd_ready`.
- Both may happen in the same cycle. `count` is then unchanged, and the order of data is preserved.
- When full, a write is refused (`wr_ready` is low) **even if a read happens in the same cycle**: there is no bypass.
- When empty, `rd_data` is don't-care; nothing may be read.
- Data comes out in exactly the order it went in, with nothing lost or duplicated.

Verification focus: ordering under random back-pressure on both sides; full and empty
boundaries; simultaneous read and write at count 0, 1, DEPTH-1 and DEPTH; reset in the middle of traffic.
