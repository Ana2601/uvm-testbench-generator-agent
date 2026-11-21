# apb_regs: APB3 register block

An APB3 completer with four 32-bit-aligned registers. Zero wait states.

| Port | Dir | Width | Meaning |
|---|---|---|---|
| `pclk`, `presetn` | in | 1 | APB clock, asynchronous active-low reset |
| `psel`, `penable`, `pwrite` | in | 1 | APB control |
| `paddr` | in | 4 | byte address |
| `pwdata` | in | 32 | write data |
| `prdata` | out | 32 | read data |
| `pready` | out | 1 | always 1: every transfer completes in its access phase |
| `pslverr` | out | 1 | error response, meaningful in the access phase |

Register map (all reset to 0):

| Address | Name | Access | Behaviour |
|---|---|---|---|
| 0x0 | CTRL | RW | bits [7:0] stored; bits [31:8] read as 0. A write sets STAT[1] |
| 0x4 | DATA | RW | 32 bits. A write increments WCNT and sets STAT[0] |
| 0x8 | WCNT | RO | number of DATA writes since reset, 16 bits, wraps. A write is an error with no effect |
| 0xC | STAT | W1C | 2 bits. Writing a 1 to a bit clears it; writing 0 leaves it. Bits [31:2] read as 0 |

Protocol:

- A transfer has a setup phase (`psel=1, penable=0`), then an access phase
  (`psel=1, penable=1`). Writes take effect at the rising edge that ends the access phase.
- In the access phase, `pslverr = 1` for any address not in the map (including
  unaligned addresses like 0x1) and for a write to WCNT. Such a transfer changes no state.
- `pslverr` is 0 outside an access phase. `prdata` is only defined in the access phase of a read.

Verification focus: reset values; write then read back for every register; RO and W1C
semantics; error responses; back-to-back transfers; idle cycles between transfers.
