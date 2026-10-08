//============================================================================
// atm_top.v  -  ATM Controller top level
//
//   atm_top
//    |- pin_verification        (pin_entry + comparator + attempt_counter)
//    |- account_manager         (stored PINs, locked flags)
//    |- balance_manager         (balances)
//    |- transaction_controller  (latch + validate amount)
//    |- timeout_timer           (in atm_fsm.v)
//    '- atm_fsm                 (main controller)
//============================================================================
module atm_top #(
    parameter TIMEOUT_CYCLES = 1000,
    parameter MAX_ATTEMPTS   = 3
) (
    input         clk,
    input         rst,
    // user side
    input         card_in,
    input  [1:0]  acct_sel,
    input  [3:0]  digit,
    input         digit_valid,     // 1-cycle pulse
    input         enter,           // 1-cycle pulse
    input         cancel,          // 1-cycle pulse
    input  [1:0]  option,          // 00 balance, 01 withdraw, 10 deposit, 11 exit
    input  [15:0] amount,
    // admin side
    input         admin_unlock,    // 1-cycle pulse
    input  [1:0]  admin_acct,
    // outputs
    output        request_pin,
    output        pin_ok,
    output        cash_out,
    output [15:0] cash_amount,
    output        deposit_done,
    output        insufficient_funds,
    output        txn_error,
    output        card_locked,
    output        eject_card,
    output [15:0] balance_out,     // 0 unless authenticated
    output [3:0]  state_out
);
    wire [1:0]  acct_q, att_cnt;
    wire [15:0] amt_q, stored_pin, balance;
    wire [2:0]  pin_count;
    wire        op_q, acct_locked, timeout, pin_match;
    wire        pin_clr, collect_digits, att_inc, att_clr, lock_en, wr_en, timer_en;
    wire        latch_withdraw, latch_deposit, amt_zero, amt_gt_bal, dep_ovf;
    wire        authenticated, show_balance;

    assign pin_ok      = authenticated;
    assign cash_amount = amt_q;
    assign balance_out = authenticated ? balance : 16'd0;

    pin_verification u_pinv (
        .clk(clk), .rst(rst), .acct(acct_q),
        .pin_clr(pin_clr), .pin_en(digit_valid & collect_digits), .digit(digit),
        .stored_pin(stored_pin),
        .att_inc(att_inc), .att_clr(att_clr),
        .unlock_en(admin_unlock), .unlock_acct(admin_acct),
        .pin_count(pin_count), .pin_match(pin_match), .att_cnt(att_cnt)
    );

    account_manager u_acct (
        .clk(clk), .rst(rst), .acct(acct_q),
        .lock_en(lock_en), .unlock_en(admin_unlock), .unlock_acct(admin_acct),
        .pin_out(stored_pin), .locked_out(acct_locked)
    );

    balance_manager u_bal (
        .clk(clk), .rst(rst), .acct(acct_q),
        .wr_en(wr_en), .op(op_q), .amount(amt_q),
        .bal_out(balance)
    );

    transaction_controller u_txn (
        .clk(clk), .rst(rst),
        .latch_withdraw(latch_withdraw), .latch_deposit(latch_deposit),
        .amount_in(amount), .balance(balance),
        .amt_q(amt_q), .op_q(op_q),
        .amt_zero(amt_zero), .amt_gt_bal(amt_gt_bal), .dep_ovf(dep_ovf)
    );

    timeout_timer #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) u_timer (
        .clk(clk), .rst(rst), .en(timer_en),
        .activity(digit_valid | enter | cancel), .timeout(timeout)
    );

    atm_fsm #(.MAX_ATTEMPTS(MAX_ATTEMPTS)) u_fsm (
        .clk(clk), .rst(rst),
        .card_in(card_in), .acct_sel(acct_sel), .enter(enter), .cancel(cancel),
        .option(option),
        .timeout(timeout), .pin_count(pin_count), .pin_match(pin_match),
        .att_cnt(att_cnt), .acct_locked(acct_locked),
        .amt_zero(amt_zero), .amt_gt_bal(amt_gt_bal), .dep_ovf(dep_ovf), .op_q(op_q),
        .acct_q(acct_q), .pin_clr(pin_clr), .collect_digits(collect_digits),
        .att_inc(att_inc), .att_clr(att_clr), .lock_en(lock_en),
        .latch_withdraw(latch_withdraw), .latch_deposit(latch_deposit),
        .wr_en(wr_en), .timer_en(timer_en),
        .authenticated(authenticated), .cash_out(cash_out),
        .deposit_done(deposit_done), .insufficient_funds(insufficient_funds),
        .txn_error(txn_error), .card_locked(card_locked),
        .eject_card(eject_card), .show_balance(show_balance),
        .request_pin(request_pin), .state_out(state_out)
    );
endmodule
