# uart_tx: UART transmitter, 8N1

Parameter: `CLKS_PER_BIT = 4` (clock cycles per bit on the line).

| Port | Dir | Width | Meaning |
|---|---|---|---|
| `clk` | in | 1 | clock, rising edge |
| `rst_n` | in | 1 | asynchronous active-low reset |
| `tx_valid` | in | 1 | request to send `tx_data` |
| `tx_data` | in | 8 | byte to send |
| `tx_ready` | out | 1 | transmitter is idle and will accept a byte |
| `txd` | out | 1 | serial line, idles high |

Behaviour:

- After reset: `txd = 1`, `tx_ready = 1`.
- A byte is accepted on a rising edge where `tx_valid && tx_ready`. `tx_ready` drops in the
  following cycle and stays low until the frame is complete.
- Frame on `txd`, starting the cycle after acceptance. Each bit lasts exactly
  `CLKS_PER_BIT` cycles:
  - one start bit (0);
  - 8 data bits, LSB first;
  - one stop bit (1).
- `tx_ready` rises again in the first cycle after the stop bit. A byte can be accepted
  in that same cycle, giving back-to-back frames with no extra idle bit.
- `tx_data` only needs to be valid in the acceptance cycle.

Verification focus: data patterns (0x00, 0xFF, alternating bits, random); back-to-back
frames; `tx_valid` held high continuously; `tx_valid` asserted while busy (must be
ignored); exact bit timing; reset in the middle of a frame.
