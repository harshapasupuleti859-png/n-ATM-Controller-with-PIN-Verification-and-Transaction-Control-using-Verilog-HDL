//============================================================================
// transaction_controller.v
// Latches the requested transaction (operation + amount) and validates it
// against the current balance.
//   amt_zero    : requested amount is 0 (ignored)
//   amt_gt_bal  : amount > balance  (withdraw would overdraw)
//   dep_ovf     : balance + amount overflows 16 bits (deposit rejected)
//============================================================================
module transaction_controller (
    input         clk,
    input         rst,
    input         latch_withdraw,  // FSM: user confirmed a withdraw amount
    input         latch_deposit,   // FSM: user confirmed a deposit amount
    input  [15:0] amount_in,       // live amount from the user
    input  [15:0] balance,         // balance of current account
    output [15:0] amt_q,           // latched amount
    output        op_q,            // latched operation (0=withdraw, 1=deposit)
    output        amt_zero,
    output        amt_gt_bal,
    output        dep_ovf
);
    localparam OP_WITHDRAW = 1'b0;
    localparam OP_DEPOSIT  = 1'b1;

    reg [15:0] amt_r;
    reg        op_r;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            amt_r <= 16'd0;
            op_r  <= OP_WITHDRAW;
        end else if (latch_withdraw) begin
            amt_r <= amount_in;
            op_r  <= OP_WITHDRAW;
        end else if (latch_deposit) begin
            amt_r <= amount_in;
            op_r  <= OP_DEPOSIT;
        end
    end

    wire [16:0] dep_sum = {1'b0, balance} + {1'b0, amount_in};

    assign amt_q      = amt_r;
    assign op_q       = op_r;
    assign amt_zero   = (amount_in == 16'd0);
    assign amt_gt_bal = (amount_in > balance);
    assign dep_ovf    = dep_sum[16];
endmodule
