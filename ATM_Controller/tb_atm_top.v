//============================================================================
// Self-checking testbench for atm_top  (LEVEL 1)
// Compile: iverilog -o sim *.v   then   vvp sim
// Waveform: gtkwave dump.vcd
//
// Default data in the DUT:
//   acct0: PIN 1234, balance  5000
//   acct1: PIN 4321, balance 10000
//   acct2: PIN 1111, balance   250
//   acct3: PIN 9999, balance     0
//============================================================================
`timescale 1ns/1ps

module tb_atm_top;

    // ---------- state names (must match design) ----------
    localparam [3:0] IDLE=0, CARD_IN=1, PIN_ENTRY=2, PIN_CHECK=3, PIN_FAIL=4,
                     MENU=5, BALANCE=6, WITHDRAW=7, DEPOSIT=8, UPDATE=9,
                     TXN_FAIL=10, LOCKED=11, EJECT=12;

    localparam TIMEOUT = 50;               // short timeout for simulation

    // ---------- DUT signals ----------
    reg         clk = 0, rst = 0;
    reg         card_in = 0;
    reg  [1:0]  acct_sel = 0;
    reg  [3:0]  digit = 0;
    reg         digit_valid = 0, enter = 0, cancel = 0;
    reg  [1:0]  option = 0;
    reg  [15:0] amount = 0;
    reg         admin_unlock = 0;
    reg  [1:0]  admin_acct = 0;

    wire        request_pin, pin_ok, cash_out, deposit_done;
    wire        insufficient_funds, txn_error, card_locked, eject_card;
    wire [15:0] cash_amount, balance_out;
    wire [3:0]  state_out;

    atm_top #(.TIMEOUT_CYCLES(TIMEOUT), .MAX_ATTEMPTS(3)) dut (
        .clk(clk), .rst(rst), .card_in(card_in), .acct_sel(acct_sel),
        .digit(digit), .digit_valid(digit_valid), .enter(enter), .cancel(cancel),
        .option(option), .amount(amount),
        .admin_unlock(admin_unlock), .admin_acct(admin_acct),
        .request_pin(request_pin), .pin_ok(pin_ok), .cash_out(cash_out),
        .cash_amount(cash_amount), .deposit_done(deposit_done),
        .insufficient_funds(insufficient_funds), .txn_error(txn_error),
        .card_locked(card_locked), .eject_card(eject_card),
        .balance_out(balance_out), .state_out(state_out)
    );

    // ---------- clock ----------
    always #5 clk = ~clk;                  // 100 MHz

    // ---------- scoreboard ----------
    integer pass_cnt = 0, fail_cnt = 0;

    task check;
        input [255:0] name;
        input         cond;
        begin
            if (cond) begin
                pass_cnt = pass_cnt + 1;
                $display("  [PASS] %0s", name);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("  [FAIL] %0s   (t=%0t state=%0d)", name, $time, state_out);
            end
        end
    endtask

    // Sticky flags: catch 1-cycle output pulses
    reg saw_cash = 0, saw_dep = 0, saw_insuff = 0, saw_txnerr = 0,
        saw_locked = 0, saw_eject = 0;
    reg [15:0] last_cash_amt = 0;
    always @(posedge clk) begin
        if (cash_out)           begin saw_cash = 1; last_cash_amt = cash_amount; end
        if (deposit_done)       saw_dep    = 1;
        if (insufficient_funds) saw_insuff = 1;
        if (txn_error)          saw_txnerr = 1;
        if (card_locked)        saw_locked = 1;
        if (eject_card)         saw_eject  = 1;
    end
    task clear_flags;
        begin
            saw_cash = 0; saw_dep = 0; saw_insuff = 0;
            saw_txnerr = 0; saw_locked = 0; saw_eject = 0;
        end
    endtask

    // ---------- stimulus helpers (drive on negedge to avoid races) ----------
    task tick;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) @(negedge clk);
        end
    endtask

    task do_reset;
        begin
            @(negedge clk); rst = 1;
            @(negedge clk); @(negedge clk); rst = 0;
            @(negedge clk);
        end
    endtask

    task insert_card;
        input [1:0] a;
        begin
            @(negedge clk); acct_sel = a; card_in = 1;
            tick(3);                          // IDLE -> CARD_IN -> PIN_ENTRY/LOCKED
        end
    endtask

    task remove_card;
        begin
            @(negedge clk); card_in = 0;
            tick(3);
        end
    endtask

    task press_digit;
        input [3:0] d;
        begin
            @(negedge clk); digit = d; digit_valid = 1;
            @(negedge clk); digit_valid = 0;
        end
    endtask

    task type_pin;
        input [15:0] p;
        begin
            press_digit(p[15:12]);
            press_digit(p[11:8]);
            press_digit(p[7:4]);
            press_digit(p[3:0]);
        end
    endtask

    task press_enter;
        begin
            @(negedge clk); enter = 1;
            @(negedge clk); enter = 0;
        end
    endtask

    task press_cancel;
        begin
            @(negedge clk); cancel = 1;
            @(negedge clk); cancel = 0;
        end
    endtask

    task admin_unlock_acct;
        input [1:0] a;
        begin
            @(negedge clk); admin_acct = a; admin_unlock = 1;
            @(negedge clk); admin_unlock = 0;
            tick(1);
        end
    endtask

    // Enter PIN + ENTER and let the FSM settle (PIN_CHECK -> MENU / PIN_FAIL ...)
    task submit_pin;
        input [15:0] p;
        begin
            type_pin(p);
            press_enter;
            tick(3);
        end
    endtask

    // Choose a menu option
    task menu_select;
        input [1:0] opt;
        begin
            @(negedge clk); option = opt;
            press_enter;
            tick(1);
        end
    endtask

    // Withdraw / deposit helpers (must be in MENU)
    task do_withdraw;
        input [15:0] amt;
        begin
            menu_select(2'b01);
            @(negedge clk); amount = amt;
            press_enter;
            tick(3);
        end
    endtask

    task do_deposit;
        input [15:0] amt;
        begin
            menu_select(2'b10);
            @(negedge clk); amount = amt;
            press_enter;
            tick(3);
        end
    endtask

    // Read a balance through the menu (checks balance_out port)
    task read_balance;
        output [15:0] b;
        begin
            menu_select(2'b00);
            b = balance_out;
            press_enter;                      // back to MENU
            tick(1);
        end
    endtask

    // ---------- main test ----------
    reg [15:0] bal;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_atm_top);

        $display("\n=========== ATM CONTROLLER TESTBENCH ===========");

        //------------------------------------------------------------
        $display("\nTEST 1: reset state");
        do_reset;
        check("state is IDLE after reset", state_out == IDLE);
        check("no outputs active", !pin_ok && !cash_out && !card_locked && !eject_card);

        //------------------------------------------------------------
        $display("\nTEST 2: valid PIN, balance, withdraw, deposit (acct0)");
        insert_card(2'd0);
        check("PIN requested", state_out == PIN_ENTRY && request_pin);
        submit_pin(16'h1234);
        check("correct PIN -> MENU", state_out == MENU);
        check("pin_ok asserted", pin_ok);

        read_balance(bal);
        check("balance = 5000", bal == 16'd5000);
        check("still in MENU", state_out == MENU);

        clear_flags;
        do_withdraw(16'd1000);
        check("cash_out pulsed", saw_cash);
        check("cash amount = 1000", last_cash_amt == 16'd1000);
        check("balance in memory = 4000", dut.u_bal.bal_mem[0] == 16'd4000);
        check("back in MENU after withdraw", state_out == MENU);

        clear_flags;
        do_deposit(16'd500);
        check("deposit_done pulsed", saw_dep);
        check("balance in memory = 4500", dut.u_bal.bal_mem[0] == 16'd4500);

        read_balance(bal);
        check("balance_out = 4500", bal == 16'd4500);

        //------------------------------------------------------------
        $display("\nTEST 3: insufficient funds (acct0, balance unchanged)");
        clear_flags;
        do_withdraw(16'd9999);
        check("insufficient_funds flagged", saw_insuff);
        check("in TXN_FAIL state", state_out == TXN_FAIL);
        check("balance unchanged = 4500", dut.u_bal.bal_mem[0] == 16'd4500);
        press_enter; tick(2);
        check("ENTER returns to MENU", state_out == MENU);

        //------------------------------------------------------------
        $display("\nTEST 4: withdraw exactly full balance, then zero-amount request");
        do_deposit(16'd0);
        check("zero deposit ignored (MENU)", state_out == MENU);
        do_withdraw(16'd4500);
        check("withdraw full balance -> 0", dut.u_bal.bal_mem[0] == 16'd0);
        do_deposit(16'd4500);                 // restore
        check("balance restored = 4500", dut.u_bal.bal_mem[0] == 16'd4500);

        //------------------------------------------------------------
        $display("\nTEST 5: deposit overflow rejected");
        clear_flags;
        do_deposit(16'd65535);
        check("txn_error on overflow", saw_txnerr);
        check("not flagged as insufficient funds", !saw_insuff);
        check("balance unchanged = 4500", dut.u_bal.bal_mem[0] == 16'd4500);
        press_enter; tick(2);

        //------------------------------------------------------------
        $display("\nTEST 6: exit via menu option, card removal");
        clear_flags;
        menu_select(2'b11);
        check("EXIT -> EJECT", state_out == EJECT && saw_eject);
        check("outputs cleared (pin_ok=0)", !pin_ok);
        remove_card;
        check("card removed -> IDLE", state_out == IDLE);

        //------------------------------------------------------------
        $display("\nTEST 7: one wrong PIN then correct PIN (acct1)");
        insert_card(2'd1);
        submit_pin(16'h0000);
        check("wrong PIN -> back to PIN_ENTRY", state_out == PIN_ENTRY);
        check("not authenticated", !pin_ok);
        check("PIN buffer cleared for retry", dut.u_pinv.u_entry.count == 0);
        submit_pin(16'h4321);
        check("correct PIN -> MENU", state_out == MENU);
        read_balance(bal);
        check("acct1 balance = 10000", bal == 16'd10000);
        press_cancel; tick(2);
        check("CANCEL -> EJECT", state_out == EJECT);
        remove_card;

        //------------------------------------------------------------
        $display("\nTEST 8: three wrong PINs lock the card (acct2)");
        clear_flags;
        insert_card(2'd2);
        submit_pin(16'h0001);
        check("attempt 1 wrong -> PIN_ENTRY", state_out == PIN_ENTRY);
        submit_pin(16'h0002);
        check("attempt 2 wrong -> PIN_ENTRY", state_out == PIN_ENTRY);
        submit_pin(16'h0003);
        check("attempt 3 wrong -> LOCKED", state_out == LOCKED);
        check("card_locked flagged", saw_locked);
        press_cancel; tick(2);
        check("CANCEL -> EJECT", state_out == EJECT);
        remove_card;

        $display("\nTEST 9: locked card stays locked even with correct PIN");
        clear_flags;
        insert_card(2'd2);
        check("re-inserted locked card -> LOCKED", state_out == LOCKED);
        check("cannot authenticate", !pin_ok);
        type_pin(16'h1111);
        press_enter; tick(2);
        check("keypad ignored while locked", state_out == LOCKED);
        remove_card;
        check("card removed -> IDLE", state_out == IDLE);

        $display("\nTEST 10: admin unlock restores access (acct2)");
        admin_unlock_acct(2'd2);
        insert_card(2'd2);
        check("after unlock -> PIN_ENTRY", state_out == PIN_ENTRY);
        submit_pin(16'h1111);
        check("correct PIN -> MENU", state_out == MENU);
        do_withdraw(16'd250);
        check("acct2 balance = 0", dut.u_bal.bal_mem[2] == 16'd0);
        menu_select(2'b11);
        remove_card;

        //------------------------------------------------------------
        $display("\nTEST 11: attempt counter clears after correct PIN (acct3)");
        insert_card(2'd3);
        submit_pin(16'h0000);
        submit_pin(16'h0000);
        check("2 wrong attempts, still PIN_ENTRY", state_out == PIN_ENTRY);
        submit_pin(16'h9999);
        check("correct PIN -> MENU", state_out == MENU);
        check("attempt counter cleared", dut.u_pinv.u_att.cnt[3] == 0);
        menu_select(2'b11);
        remove_card;
        insert_card(2'd3);
        submit_pin(16'h0000);
        submit_pin(16'h0000);
        check("2 more wrong attempts do NOT lock", state_out == PIN_ENTRY);
        press_cancel; tick(2);
        remove_card;

        $display("\nTEST 12: wrong attempts persist across card re-insertion (acct3)");
        clear_flags;
        insert_card(2'd3);
        submit_pin(16'h0000);                 // counter was 2 -> now locks
        check("3rd cumulative wrong PIN -> LOCKED", state_out == LOCKED);
        remove_card;
        admin_unlock_acct(2'd3);

        //------------------------------------------------------------
        $display("\nTEST 13: incomplete PIN and invalid digits");
        insert_card(2'd0);
        press_digit(4'd1); press_digit(4'd2); press_digit(4'd3);
        press_enter; tick(2);
        check("ENTER with 3 digits ignored", state_out == PIN_ENTRY);
        press_digit(4'd12);                   // invalid BCD digit
        check("digit > 9 ignored", dut.u_pinv.u_entry.count == 3);
        press_digit(4'd4);
        press_enter; tick(3);
        check("then 1234 accepted -> MENU", state_out == MENU);

        //------------------------------------------------------------
        $display("\nTEST 14: cancel mid-transaction");
        menu_select(2'b01);
        check("in WITHDRAW state", state_out == WITHDRAW);
        @(negedge clk); amount = 16'd100;
        press_cancel; tick(2);
        check("CANCEL -> EJECT", state_out == EJECT);
        check("balance unchanged = 4500", dut.u_bal.bal_mem[0] == 16'd4500);
        remove_card;

        //------------------------------------------------------------
        $display("\nTEST 15: timeout with no input");
        insert_card(2'd0);
        submit_pin(16'h1234);
        check("in MENU", state_out == MENU);
        tick(TIMEOUT + 10);
        check("timeout -> EJECT", state_out == EJECT);
        remove_card;

        $display("\nTEST 16: timeout while waiting for PIN");
        insert_card(2'd0);
        tick(TIMEOUT + 10);
        check("PIN-entry timeout -> EJECT", state_out == EJECT);
        remove_card;

        $display("\nTEST 17: activity prevents timeout");
        insert_card(2'd0);
        submit_pin(16'h1234);
        repeat (6) begin
            tick(TIMEOUT - 15);
            press_digit(4'd5);                // keypress resets timer (ignored in MENU)
        end
        check("still in MENU after long but active session", state_out == MENU);
        press_cancel; tick(2);
        remove_card;

        //------------------------------------------------------------
        $display("\nTEST 18: card pulled out unexpectedly");
        insert_card(2'd0);
        submit_pin(16'h1234);
        check("in MENU", state_out == MENU);
        @(negedge clk); card_in = 0;
        tick(2);
        check("card removal -> EJECT/IDLE", state_out == EJECT || state_out == IDLE);
        tick(2);
        check("then IDLE", state_out == IDLE);
        check("pin_ok dropped", !pin_ok);

        $display("\nTEST 19: card pulled during PIN entry");
        insert_card(2'd1);
        press_digit(4'd4); press_digit(4'd3);
        @(negedge clk); card_in = 0;
        tick(4);
        check("-> IDLE", state_out == IDLE);
        insert_card(2'd1);
        check("PIN buffer cleared for next user", dut.u_pinv.u_entry.count == 0 && state_out == PIN_ENTRY);
        press_cancel; tick(2);
        remove_card;

        //------------------------------------------------------------
        $display("\nTEST 20: reset during a transaction");
        insert_card(2'd0);
        submit_pin(16'h1234);
        do_withdraw(16'd1000);
        check("balance now 3500", dut.u_bal.bal_mem[0] == 16'd3500);
        @(negedge clk); rst = 1;
        tick(2);
        check("reset forces IDLE", state_out == IDLE && !pin_ok);
        check("balances restored to default", dut.u_bal.bal_mem[0] == 16'd5000);
        rst = 0; tick(3);
        check("card still in -> new session asks for PIN again", state_out == PIN_ENTRY && !pin_ok);
        @(negedge clk); card_in = 0; tick(2);

        //------------------------------------------------------------
        $display("\n================================================");
        $display(" RESULT: %0d passed, %0d failed", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display(" *** ALL TESTS PASSED ***");
        else               $display(" *** SOME TESTS FAILED ***");
        $display("================================================\n");
        $finish;
    end

    // Watchdog: stops the simulation if something hangs
    initial begin
        #2_000_000;
        $display("WATCHDOG: simulation timed out");
        $finish;
    end

endmodule
