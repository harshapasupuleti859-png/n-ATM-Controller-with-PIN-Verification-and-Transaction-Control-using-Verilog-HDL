// ============================================================================
// REFERENCE ATM DESIGN  (so the software works out-of-the-box)
// Delete / replace this file with YOUR rtl/*.v files, then edit the PORT MAP
// section in sim/tb_bridge.v to match your own atm_top ports.
// ============================================================================
`timescale 1ns/1ps
module atm_top (
    input              clk,
    input              rst,
    input              card_insert,
    input      [15:0]  pin_in,        // 4 BCD digits, e.g. 16'h1234
    input              pin_enter,
    input      [1:0]   acc_sel,
    input              acc_enter,
    input      [1:0]   txn_sel,       // 0=balance 1=withdraw 2=deposit
    input      [15:0]  amount,
    input              txn_enter,
    input              back,
    input              cancel,
    input              load,          // DB -> hardware: load PIN + balance
    input      [15:0]  load_pin,
    input      [15:0]  load_bal,
    output reg [3:0]   state,
    output reg         auth_ok,
    output reg         locked,
    output reg         pin_error,
    output reg [1:0]   attempts,
    output reg [15:0]  balance,
    output reg         txn_success,
    output reg         insufficient
);
    parameter [15:0] CORRECT_PIN  = 16'h1234;
    parameter        MAX_ATTEMPTS = 3;

    localparam [3:0] IDLE=0, PIN_ENTRY=1, ACC_SELECT=2, MENU=3,
                     BALANCE=4, TXN_OK=5, INSUFF=6, LOCKED=7;

    reg [15:0] accounts [0:3];
    reg [1:0]  cur;
    reg [15:0] pin_reg;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;  auth_ok <= 0; locked <= 0; pin_error <= 0;
            attempts <= 0;  balance <= 0; txn_success <= 0; insufficient <= 0;
            cur <= 0;  pin_reg <= CORRECT_PIN;
            accounts[0] <= 16'd1000;
            accounts[1] <= 16'd2500;
            accounts[2] <= 16'd500;
            accounts[3] <= 16'd10000;
        end else if (load) begin
            pin_reg <= load_pin;  accounts[0] <= load_bal;
        end else begin
            case (state)
            IDLE: begin
                if (card_insert) begin
                    state <= PIN_ENTRY; pin_error <= 0; auth_ok <= 0;
                    txn_success <= 0;   insufficient <= 0;
                end
            end
            PIN_ENTRY: begin
                if (cancel) begin
                    state <= IDLE; pin_error <= 0;
                end else if (pin_enter) begin
                    if (pin_in == pin_reg) begin
                        auth_ok <= 1; pin_error <= 0; attempts <= 0;
                        state <= ACC_SELECT;
                    end else begin
                        pin_error <= 1;
                        attempts  <= attempts + 2'd1;
                        if (attempts == MAX_ATTEMPTS-1) begin
                            locked <= 1; state <= LOCKED;
                        end
                    end
                end
            end
            ACC_SELECT: begin
                if (cancel) begin
                    state <= IDLE; auth_ok <= 0;
                end else if (acc_enter) begin
                    cur <= acc_sel; balance <= accounts[acc_sel];
                    state <= MENU;
                end
            end
            MENU: begin
                if (cancel) begin
                    state <= IDLE; auth_ok <= 0;
                end else if (txn_enter) begin
                    case (txn_sel)
                    2'd0: state <= BALANCE;
                    2'd1: begin
                        if (amount <= accounts[cur]) begin
                            accounts[cur] <= accounts[cur] - amount;
                            balance       <= accounts[cur] - amount;
                            txn_success   <= 1; state <= TXN_OK;
                        end else begin
                            insufficient <= 1; state <= INSUFF;
                        end
                    end
                    2'd2: begin
                        accounts[cur] <= accounts[cur] + amount;
                        balance       <= accounts[cur] + amount;
                        txn_success   <= 1; state <= TXN_OK;
                    end
                    default: ;
                    endcase
                end
            end
            BALANCE, TXN_OK, INSUFF: begin
                if (cancel) begin
                    state <= IDLE; auth_ok <= 0;
                    txn_success <= 0; insufficient <= 0;
                end else if (back) begin
                    state <= MENU; txn_success <= 0; insufficient <= 0;
                end
            end
            LOCKED: ;   // stays locked until reset
            default: state <= IDLE;
            endcase
        end
    end
endmodule
