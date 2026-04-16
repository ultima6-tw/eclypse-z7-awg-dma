`timescale 1ns / 1ps

module clk_forwarding (
    input  wire clk_in,    // 來自 clk_wiz_2 的乾淨 10MHz
    input  wire is_master, // 【關鍵對齊】1: Master(發送), 0: Slave(靜默)
    input  wire locked,    // 來自 clk_wiz_2 的 locked 狀態
    output wire [1:0] clk_out 
);

    genvar i;
    generate
        for (i = 0; i < 2; i = i + 1) begin : gen_oddr
            ODDR #(
                .DDR_CLK_EDGE("OPPOSITE_EDGE"), 
                .INIT(1'b0),                    
                .SRTYPE("SYNC")                 
            ) ODDR_inst (
                .Q(clk_out[i]),    
                .C(clk_in),        
                .CE(1'b1),         
                .D1(1'b1),         
                .D2(1'b0),         
                
                // --- 邏輯修正處 ---
                // 我們希望只有當 (is_master == 1) 且 (locked == 1) 時，
                // ODDR 的 Reset (R) 才是 0 (不重置，正常輸出時鐘)。
                // 
                // 邏輯推導：
                // R = 1 代表輸出強制為 0。
                // 當 !is_master (它是Slave) -> R 變為 1
                // 當 !locked    (時鐘不穩) -> R 變為 1
                .R(~is_master | ~locked),   
                
                .S(1'b0)           
            );
        end
    endgenerate

endmodule