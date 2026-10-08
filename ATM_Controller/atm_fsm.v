//============================================================================
// atm_fsm.v
// Main ATM controller (13-state FSM, Moore outputs) + idle timeout timer.
//   enter / cancel / digit_valid are ONE-CYCLE pulses.
//============================================================================

module timeout_timer #(
    parameter TIMEOUT_CYCLES = 1000    // real clock: clock_Hz * seconds
) (
    input  clk,
    input  rst,
    input  en,          // runs only while a session waits for input
    input  activity,    // any key press clears the timer
    output timeout
);
    reg [31:0] cnt;

    always @(posedge clk or posedge rst) begin
        if (rst)                    cnt <= 32'd0;
        else if (!en || activity)   cnt <= 32'd0;
        else if (cnt < TIMEOUT_CYCLES) cnt <= cnt + 32'd1;
    end

    assign timeout = (cnt >= TIMEOUT_CYCLES);
endmodule

module atm_fsm #(
    parameter MAX_ATTEMPTS = 3          // 1..4
) (
    input         clk,
    input         rst,
    // user inputs
    input         card_in,
    input  [1:0]  acct_sel,
    input         enter,
    input         cancel,
    input  [1:0]  option,               // 00 balance, 01 withdraw, 10 deposit, 11 exit
    // status from datapath
    input         timeout,
    input  [2:0]  pin_count,
    input         pin_match,
    input  [1:0]  att_cnt,
    input         acct_locked,
    input         amt_zero,
    input         amt_gt_bal,
    input         dep_ovf,
    input         op_q,
    // control to datapath
    output [1:0]  acct_q,               // account of current session
    output        pin_clr,
    output        collect_digits,
    output        att_inc,
    output        att_clr,
    output        lock_en,
    output        latch_withdraw,
    output        latch_deposit,
    output        wr_en,
    output        timer_en,
    // status outputs
    output        authenticated,
    output        cash_out,
    output        deposit_done,
    output        insufficient_funds,
    output        txn_error,
    output        card_locked,
    output        eject_card,
    output        show_balance,
    output        request_pin,
    output [3:0]  state_out
);
    localparam [3:0] IDLE      = 4'd0,
                     CARD_IN   = 4'd1,
                     PIN_ENTRY = 4'd2,
                     PIN_CHECK = 4'd3,
                     PIN_FAIL  = 4'd4,
                     MENU      = 4'd5,
                     BALANCE   = 4'd6,
                     WITHDRAW  = 4'd7,
                     DEPOSIT   = 4'd8,
                     UPDATE    = 4'd9,
                     TXN_FAIL  = 4'd10,
                     LOCKED    = 4'd11,
                     EJECT     = 4'd12;

    localparam OP_WITHDRAW = 1'b0;
    localparam OP_DEPOSIT  = 1'b1;

    reg [3:0] state, next_state;
    reg [1:0] acct_r;

    assign acct_q = acct_r;

    // ---------------- Block 1: state register ----------------
    always @(posedge clk or posedge rst) begin
        if (rst) state <= IDLE;
        else     state <= next_state;
    end

    // Session account latch (card identifies the account)
    always @(posedge clk or posedge rst) begin
        if (rst)                          acct_r <= 2'd0;
        else if (state == IDLE && card_in) acct_r <= acct_sel;
    end

    // ---------------- Block 2: next-state logic ----------------
    wire abort = cancel | timeout | ~card_in;

    always @(*) begin
        next_state = state;
        case (state)
            IDLE:      if (card_in) next_state = CARD_IN;

            CARD_IN:   next_state = acct_locked ? LOCKED : PIN_ENTRY;

            PIN_ENTRY: if (abort)
                           next_state = EJECT;
                       else if (enter && pin_count == 3'd4)
                           next_state = PIN_CHECK;

            PIN_CHECK: next_state = pin_match ? MENU : PIN_FAIL;

            PIN_FAIL:  next_state = (att_cnt >= MAX_ATTEMPTS - 1) ? LOCKED : PIN_ENTRY;

            MENU:      if (abort)
                           next_state = EJECT;
                       else if (enter) begin
                           case (option)
                               2'b00:   next_state = BALANCE;
                               2'b01:   next_state = WITHDRAW;
                               2'b10:   next_state = DEPOSIT;
                               default: next_state = EJECT;
                           endcase
                       end

            BALANCE:   if (abort)       next_state = EJECT;
                       else if (enter)  next_state = MENU;

            WITHDRAW:  if (abort)
                           next_state = EJECT;
                       else if (enter) begin
                           if (amt_zero)        next_state = MENU;
                           else if (amt_gt_bal) next_state = TXN_FAIL;
                           else                 next_state = UPDATE;
                       end

            DEPOSIT:   if (abort)
                           next_state = EJECT;
                       else if (enter) begin
                           if (amt_zero)        next_state = MENU;
                           else if (dep_ovf)    next_state = TXN_FAIL;
                           else                 next_state = UPDATE;
                       end

            UPDATE:    next_state = MENU;

            TXN_FAIL:  if (abort)       next_state = EJECT;
                       else if (enter)  next_state = MENU;

            LOCKED:    if (abort)       next_state = EJECT;

            EJECT:     if (~card_in)    next_state = IDLE;

            default:   next_state = IDLE;
        endcase
    end

    // ---------------- Block 3: outputs ----------------
    assign pin_clr        = (state == CARD_IN) || (state == PIN_CHECK) || (state == EJECT);
    assign collect_digits = (state == PIN_ENTRY);
    assign att_inc        = (state == PIN_FAIL);
    assign att_clr        = (state == PIN_CHECK) && pin_match;
    assign lock_en        = (state == PIN_FAIL) && (att_cnt >= MAX_ATTEMPTS - 1);
    assign latch_withdraw = (state == WITHDRAW) && enter;
    assign latch_deposit  = (state == DEPOSIT)  && enter;
    assign wr_en          = (state == UPDATE);

    assign timer_en = (state == PIN_ENTRY) || (state == MENU)     || (state == BALANCE) ||
                      (state == WITHDRAW)  || (state == DEPOSIT)  || (state == TXN_FAIL) ||
                      (state == LOCKED);

    assign authenticated      = (state == MENU)     || (state == BALANCE)  || (state == WITHDRAW) ||
                                (state == DEPOSIT)  || (state == UPDATE)   || (state == TXN_FAIL);
    assign cash_out           = (state == UPDATE)   && (op_q == OP_WITHDRAW);
    assign deposit_done       = (state == UPDATE)   && (op_q == OP_DEPOSIT);
    assign txn_error          = (state == TXN_FAIL);
    assign insufficient_funds = (state == TXN_FAIL) && (op_q == OP_WITHDRAW);
    assign card_locked        = (state == LOCKED);
    assign eject_card         = (state == EJECT);
    assign show_balance       = (state == BALANCE);
    assign request_pin        = (state == PIN_ENTRY);
    assign state_out          = state;
endmodule
