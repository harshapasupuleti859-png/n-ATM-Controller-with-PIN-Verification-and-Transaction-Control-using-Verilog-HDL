//============================================================================
// pin_verification.v
// PIN entry buffer, PIN comparison and wrong-attempt counting.
//   pin_entry       : 4-digit BCD shift register + digit counter
//   attempt_counter : wrong-PIN counter, one per account (saturates at 3)
//   pin_verification: wrapper = entry + comparator + attempt counter
//============================================================================

module pin_entry (
    input             clk,
    input             rst,
    input             clr,        // clear buffer and counter
    input             en,         // accept a digit this cycle
    input      [3:0]  digit,      // BCD digit
    output reg [15:0] pin_reg,    // first digit in MSB
    output reg [2:0]  count       // digits entered (0..4)
);
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pin_reg <= 16'd0;
            count   <= 3'd0;
        end else if (clr) begin
            pin_reg <= 16'd0;
            count   <= 3'd0;
        end else if (en && (digit <= 4'd9) && (count < 3'd4)) begin
            pin_reg <= {pin_reg[11:0], digit};
            count   <= count + 3'd1;
        end
    end
endmodule

module attempt_counter (
    input        clk,
    input        rst,
    input  [1:0] acct,
    input        inc,           // wrong PIN
    input        clr,           // correct PIN
    input        unlock_en,     // admin unlock clears another account
    input  [1:0] unlock_acct,
    output [1:0] count
);
    reg [1:0] cnt [0:3];
    integer i;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 4; i = i + 1) cnt[i] <= 2'd0;
        end else begin
            if (clr)
                cnt[acct] <= 2'd0;
            else if (inc && cnt[acct] != 2'd3)
                cnt[acct] <= cnt[acct] + 2'd1;

            if (unlock_en)
                cnt[unlock_acct] <= 2'd0;
        end
    end

    assign count = cnt[acct];
endmodule

module pin_verification (
    input         clk,
    input         rst,
    input  [1:0]  acct,          // account of the current session
    input         pin_clr,       // clear entry buffer
    input         pin_en,        // accept digit (digit_valid & collecting)
    input  [3:0]  digit,
    input  [15:0] stored_pin,    // from account_manager
    input         att_inc,
    input         att_clr,
    input         unlock_en,
    input  [1:0]  unlock_acct,
    output [2:0]  pin_count,
    output        pin_match,
    output [1:0]  att_cnt
);
    wire [15:0] entered_pin;

    pin_entry u_entry (
        .clk(clk), .rst(rst), .clr(pin_clr), .en(pin_en), .digit(digit),
        .pin_reg(entered_pin), .count(pin_count)
    );

    attempt_counter u_att (
        .clk(clk), .rst(rst), .acct(acct), .inc(att_inc), .clr(att_clr),
        .unlock_en(unlock_en), .unlock_acct(unlock_acct), .count(att_cnt)
    );

    assign pin_match = (entered_pin == stored_pin);
endmodule
