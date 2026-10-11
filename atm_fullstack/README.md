# ATM Controller – Software Front-End for your Verilog Design

A browser-based ATM screen (keypad, menus, live signal panel) that drives your
Verilog design through **Icarus Verilog**. No Python packages to install.

```
Browser UI <-> server.py <-> session.cmd -> Icarus Verilog (vvp) -> ATM| status lines
                                             (rtl/*.v + sim/tb_bridge.v)
```

## 1. Install (one time)
| Tool | Where |
|---|---|
| Python 3.8+ | https://python.org (tick "Add to PATH") |
| Icarus Verilog | Windows: https://bleyer.org/icarus/ · Ubuntu: `sudo apt install iverilog` · macOS: `brew install icarus-verilog` |
| GTKWave (optional, waveforms) | https://gtkwave.sourceforge.net |

Check: `iverilog -V` and `python --version` should both print a version.

## 2. Run it
- Windows: double-click `run_windows.bat`
- Mac/Linux: `./run_mac_linux.sh`
- or: `python server.py`, then open http://localhost:8000

The badge (top right) shows **Icarus Verilog simulation** (real Verilog) or
**Python model (mock)** (iverilog not found; the UI still works as a demo).
Demo PIN: **1234**.

## 3. Connect YOUR Verilog code
The zip ships with a small reference `rtl/atm_top.v` so it runs immediately.

1. **Delete** `rtl/atm_top.v` and copy your own files into `rtl/`
   (pin_verification.v, account_manager.v, balance_manager.v,
   transaction_controller.v, atm_fsm.v, atm_top.v).
2. Open `sim/tb_bridge.v` and edit the three `>>> EDIT <<<` sections:
   - EDIT 1 / 2: make the `atm_top dut (...)` port list match YOUR top module
     (names and widths).
   - EDIT 3: the `do_*` tasks decide how each button drives your inputs
     (e.g. if your PIN is entered digit by digit, loop over 4 digits in `do_pin`).
   - The `report` task prints the status line; point it at your output signals.
     Keep the `ATM|key=value|...` format.
3. Open `config.json` and set `state_names` to your FSM state encoding
   (number -> IDLE, PIN_ENTRY, ACCOUNT_SELECT, MENU, BALANCE, TXN_OK,
   INSUFFICIENT or LOCKED).
4. Restart `server.py`. Compile errors show in a red box on the page.

Commands the bridge understands (`sim/session.cmd`, auto-generated):
`RESET`, `CARD`, `PIN <hex-as-decimal>`, `ACC <n>`, `TXN <0|1|2> <amount>`, `BACK`, `CANCEL`
(TXN 0 = balance, 1 = withdraw, 2 = deposit; PIN 1234 is sent as 0x1234 = 4660).

## 4. Test without the UI
```
python tests/test_scenarios.py          # README test table, auto backend
python tests/test_scenarios.py --mock   # Python model only
```

## 5. Waveforms
Each run writes `sim/session.vcd`. Use "Download waveform" on the page and open it
in GTKWave (or upload to EPWave).

## Notes
- Each click replays the whole session from reset, so the screen always reflects
  exactly what your Verilog produced.
- The reference design: 16-bit balances, 4 accounts, lock after 3 wrong PINs.

---
# FULL-STACK VERSION (app.py)
`python app.py` (or run_windows.bat / run_mac_linux.sh) -> http://localhost:8000
- **Frontend**: web/bank.html (sign in, register, deposit/withdraw/balance, history, live Verilog output)
- **Backend**: app.py (REST API: /api/login /api/register /api/me /api/txn /api/logout)
- **Database**: SQLite `bank.db` (accounts + transactions), created on first run
- **Hardware**: every PIN check, 3-attempt lock, withdrawal, deposit and insufficient-funds
  decision is made by your Verilog through sim/tb_bridge.v. The database loads the account's
  PIN + balance into the design with the new `LOAD` command (inputs `load`, `load_pin`, `load_bal`
  in the reference rtl/atm_top.v). When you plug in your own RTL, add those load inputs
  (or a similar backdoor) and edit tb_bridge.v EDIT 1-3 as described above.
- Demo accounts: card 1001 / PIN 1234, card 1002 / PIN 4321. The original demo UI is still in web/index.html + server.py.
- Demo limitation: PINs are stored in plain text because the hardware model needs the raw value.
