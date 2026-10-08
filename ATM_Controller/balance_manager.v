//============================================================================
// balance_manager.v
// Balance storage for 4 accounts; applies withdraw / deposit when wr_en=1.
// The transaction_controller guarantees the operation is valid.
//   Demo data: acct0 5000, acct1 10000, acct2 250, acct3 0
//============================================================================
module balance_manager (
    input         clk,
    input         rst,
    input  [1:0]  acct,
    input         wr_en,         // commit transaction
    input         op,            // 0 = withdraw, 1 = deposit
    input  [15:0] amount,
    output [15:0] bal_out        // balance of selected account
);
    localparam OP_DEPOSIT = 1'b1;

    reg [15:0] bal_mem [0:3];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            bal_mem[0] <= 16'd5000;
            bal_mem[1] <= 16'd10000;
            bal_mem[2] <= 16'd250;
            bal_mem[3] <= 16'd0;
        end else if (wr_en) begin
            if (op == OP_DEPOSIT)
                bal_mem[acct] <= bal_mem[acct] + amount;
            else
                bal_mem[acct] <= bal_mem[acct] - amount;
        end
    end

    assign bal_out = bal_mem[acct];
endmodule
