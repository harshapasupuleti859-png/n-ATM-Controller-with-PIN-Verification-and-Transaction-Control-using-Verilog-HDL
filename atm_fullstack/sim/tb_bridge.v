// ============================================================================
// tb_bridge.v  -  the "bridge" between the software (Python/web UI) and Verilog
//
// How it works:
//   1. The software writes the user's actions to  sim/session.cmd, one per line:
//          CMD  A  B          e.g.  PIN 4660 0     TXN 1 200
//   2. It runs this testbench with Icarus Verilog (vvp).
//   3. After every command this file prints one line starting with  ATM|
//      which the software parses and shows on screen.
//
// To connect YOUR design, edit only the 3 sections marked  >>> EDIT <<<
// ============================================================================
`timescale 1ns/1ps
module tb_bridge;

    // ---------------- >>> EDIT 1: signals that connect to your DUT <<< ------
    reg         clk, rst;
    reg         load;
    reg  [15:0] load_pin, load_bal;
    reg         card_insert, pin_enter, acc_enter, txn_enter, back, cancel;
    reg  [15:0] pin_in, amount;
    reg  [1:0]  acc_sel, txn_sel;

    wire [3:0]  state;
    wire        auth_ok, locked, pin_error, txn_success, insufficient;
    wire [1:0]  attempts;
    wire [15:0] balance;

    // ---------------- >>> EDIT 2: instantiate YOUR top module <<< ----------
    atm_top dut (
        .clk(clk), .rst(rst),
        .card_insert(card_insert),
        .pin_in(pin_in),   .pin_enter(pin_enter),
        .acc_sel(acc_sel), .acc_enter(acc_enter),
        .txn_sel(txn_sel), .amount(amount), .txn_enter(txn_enter),
        .back(back), .cancel(cancel),
        .load(load), .load_pin(load_pin), .load_bal(load_bal),
        .state(state), .auth_ok(auth_ok), .locked(locked),
        .pin_error(pin_error), .attempts(attempts), .balance(balance),
        .txn_success(txn_success), .insufficient(insufficient)
    );

    // ---------------- clock -------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    task tick;   begin @(posedge clk); #1; end endtask
    task settle; begin tick; tick; tick;   end endtask

    // ---------------- >>> EDIT 3: how each command drives your inputs <<< ---
    task do_reset;
        begin rst = 1; tick; tick; rst = 0; settle; end
    endtask
    task do_load;  input [15:0] p; input [15:0] bl;
        begin load_pin = p; load_bal = bl; load = 1; tick; load = 0; settle; end
    endtask
    task do_card;
        begin card_insert = 1; tick; card_insert = 0; settle; end
    endtask
    task do_pin;   input [15:0] v;
        begin pin_in = v; pin_enter = 1; tick; pin_enter = 0; settle; end
    endtask
    task do_acc;   input [1:0] v;
        begin acc_sel = v; acc_enter = 1; tick; acc_enter = 0; settle; end
    endtask
    task do_txn;   input [1:0] t; input [15:0] amt;
        begin txn_sel = t; amount = amt; txn_enter = 1; tick; txn_enter = 0; settle; end
    endtask
    task do_back;
        begin back = 1; tick; back = 0; settle; end
    endtask
    task do_cancel;
        begin cancel = 1; tick; cancel = 0; settle; end
    endtask

    // Status line the software reads. Keep the "ATM|key=value|..." format;
    // you can rename the signals on the right-hand side to match your design.
    task report; input integer n;
        begin
            $display("ATM|idx=%0d|state=%0d|auth=%0d|locked=%0d|err=%0d|attempts=%0d|balance=%0d|ok=%0d|insuf=%0d",
                     n, state, auth_ok, locked, pin_error, attempts, balance,
                     txn_success, insufficient);
        end
    endtask

    // ---------------- main loop (no need to edit) --------------------------
    integer fd, r, idx, a, b;
    reg [8*8-1:0] op;

    initial begin
        $dumpfile("session.vcd");
        $dumpvars(0, tb_bridge);

        rst = 0; card_insert = 0; pin_enter = 0; acc_enter = 0; txn_enter = 0;
        back = 0; cancel = 0; load = 0; load_pin = 0; load_bal = 0; pin_in = 0; amount = 0; acc_sel = 0; txn_sel = 0;
        idx = 0;

        do_reset;
        report(idx);

        fd = $fopen("session.cmd", "r");
        if (fd == 0) begin
            $display("ATM_ERROR|cannot open session.cmd");
            $finish;
        end

        while (!$feof(fd)) begin
            r = $fscanf(fd, "%s %d %d\n", op, a, b);
            if (r == 3) begin
                idx = idx + 1;
                if      (op == "RESET")  do_reset;
                else if (op == "LOAD")   do_load(a[15:0], b[15:0]);
                else if (op == "CARD")   do_card;
                else if (op == "PIN")    do_pin(a[15:0]);
                else if (op == "ACC")    do_acc(a[1:0]);
                else if (op == "TXN")    do_txn(a[1:0], b[15:0]);
                else if (op == "BACK")   do_back;
                else if (op == "CANCEL") do_cancel;
                else $display("ATM_ERROR|unknown command");
                report(idx);
            end
        end
        $fclose(fd);
        $finish;
    end
endmodule
