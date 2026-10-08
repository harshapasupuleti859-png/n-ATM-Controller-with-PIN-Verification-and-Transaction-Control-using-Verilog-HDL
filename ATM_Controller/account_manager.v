//============================================================================
// account_manager.v
// Account database: stored PIN and locked flag for 4 accounts.
//   Demo data: acct0 PIN 1234, acct1 PIN 4321, acct2 PIN 1111, acct3 PIN 9999
//============================================================================
module account_manager (
    input         clk,
    input         rst,
    input  [1:0]  acct,          // selected account
    input         lock_en,       // lock selected account
    input         unlock_en,     // admin unlock
    input  [1:0]  unlock_acct,
    output [15:0] pin_out,       // stored PIN of selected account
    output        locked_out     // locked flag of selected account
);
    reg [15:0] pin_mem [0:3];
    reg [3:0]  locked;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pin_mem[0] <= 16'h1234;
            pin_mem[1] <= 16'h4321;
            pin_mem[2] <= 16'h1111;
            pin_mem[3] <= 16'h9999;
            locked     <= 4'b0000;
        end else begin
            if (lock_en)   locked[acct]        <= 1'b1;
            if (unlock_en) locked[unlock_acct] <= 1'b0;   // wins over lock_en
        end
    end

    assign pin_out    = pin_mem[acct];
    assign locked_out = locked[acct];
endmodule
