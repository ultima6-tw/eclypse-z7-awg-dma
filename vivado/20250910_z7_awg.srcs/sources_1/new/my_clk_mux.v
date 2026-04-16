`timescale 1ns / 1ps

module my_clk_mux (
    input  wire ref_clk,       // 穩定的參考時鐘 (建議用 PS 時鐘或 125MHz)
    input  wire rst_n,         // 系統全局復位

    // 時鐘輸入
    input  wire clk_in0,       // 內部 10 MHz
    input  wire clk_in1,       // 外部 10 MHz (源自 B15)

    // 控制與狀態
    input  wire sel,           // 0: 內部, 1: 外部
    input  wire wiz_locked_in, // 後級 Clocking Wizard 的 Locked 訊號
    
    // 輸出
    output wire clk_out,       // 輸出給後級 Clocking Wizard
    output reg  wiz_rst_out,   // 輸出給後級 Clocking Wizard 的 Reset
    output wire sys_rst_out,   // 輸出給後級所有邏輯的系統復位
    
    // --- 新增的輸出腳位 ---
    output wire clk_10mhz_to_pin // 輸出到外部 Pin 腳 (給其他 Slave)
);

    // -------------------------------------------------------------------------
    // 1. 硬體原語呼叫 (BUFGMUX) - 維持不變
    // -------------------------------------------------------------------------
    BUFGMUX #(
       .CLK_SEL_TYPE("ASYNC")
    ) BUFGMUX_inst (
       .O(clk_out),
       .I0(clk_in0),
       .I1(clk_in1),
       .S(sel)
    );

    // -------------------------------------------------------------------------
    // 2. 切換偵測邏輯 - 維持不變
    // -------------------------------------------------------------------------
    reg [1:0] sel_sync;
    reg       sel_delayed;
    reg [7:0] rst_counter;

    always @(posedge ref_clk or negedge rst_n) begin
        if (!rst_n) begin
            sel_sync    <= 2'b00;
            sel_delayed <= 1'b0;
        end else begin
            sel_sync    <= {sel_sync[0], sel};
            sel_delayed <= sel_sync[1];
        end
    end

    wire sel_changed = sel_sync[1] ^ sel_delayed;

    always @(posedge ref_clk or negedge rst_n) begin
        if (!rst_n) begin
            wiz_rst_out <= 1'b1;
            rst_counter <= 8'd0;
        end else if (sel_changed) begin
            wiz_rst_out <= 1'b1;
            rst_counter <= 8'd20;
        end else if (rst_counter > 0) begin
            rst_counter <= rst_counter - 1'b1;
            wiz_rst_out <= 1'b1;
        end else begin
            wiz_rst_out <= 1'b0;
        end
    end

    assign sys_rst_out = !wiz_locked_in;

    // -------------------------------------------------------------------------
    // 3. 10MHz 轉發邏輯 (Gate Control)
    // -------------------------------------------------------------------------
    // 當 sel == 0 (使用內部時鐘) 時，將 clk_in0 輸出到 Pin 腳
    // 當 sel == 1 (使用外部時鐘) 時，輸出固定為 0 (0V)
    assign clk_10mhz_to_pin = (sel == 1'b0) ? clk_in0 : 1'b0;

endmodule