`timescale 1ns / 1ps

module my_trigger_selector (
    input  wire clk,            // 使用 ref_clk (125MHz)
    input  wire rst_n,          // 系統重置 (Active Low)
    
    // 物理輸入埠
    input  wire trig_in_0,      // 內部觸發源 (例如來自 AXI GPIO，Master 模式下使用)
    input  wire trig_in_1,      // 外部觸發源 (來自 PMOD，Slave 模式下使用)
    
    // 控制訊號 (來自 AXI GPIO)
    input  wire sel,            // 選擇信號 (0: 內部, 1: 外部)
    
    // 最終輸出 (供本機 DMA 或 DAC 啟動使用)
    output wire trig_out,
    
    // --- 新增：轉發給其他板子的觸發訊號 (2 組) ---
    output wire [1:0] trig_forward_out 
);

    // -------------------------------------------------------------------------
    // 1. 雙路同步器 (防止外部訊號導致亞穩態)
    // -------------------------------------------------------------------------
    reg [1:0] sync_0, sync_1;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_0 <= 2'b0;
            sync_1 <= 2'b0;
        end else begin
            sync_0 <= {sync_0[0], trig_in_0};
            sync_1 <= {sync_1[0], trig_in_1};
        end
    end

    // -------------------------------------------------------------------------
    // 2. 本機選擇邏輯
    // -------------------------------------------------------------------------
    assign trig_out = (sel == 1'b0) ? sync_0[1] : sync_1[1];

    // -------------------------------------------------------------------------
    // 3. 轉發邏輯 (Gate Control)
    // -------------------------------------------------------------------------
    // 當 sel == 0 (Master 模式)，將同步後的內部觸發訊號轉發出去
    // 當 sel == 1 (Slave 模式)，關閉轉發輸出，維持 0V
    assign trig_forward_out = (sel == 1'b0) ? {sync_0[1], sync_0[1]} : 2'b00;

endmodule