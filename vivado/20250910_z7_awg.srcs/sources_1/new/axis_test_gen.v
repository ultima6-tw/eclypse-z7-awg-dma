`timescale 1ns / 1ps

module axis_test_gen #(
    parameter DATA_WIDTH = 32,
    // 這裡設為 14-bit 的最大值與最小值 (Offset Binary 或 2's Complement 視你的 DAC 設定而定)
    parameter VAL_HIGH   = 14'h1FFF, 
    parameter VAL_LOW    = 14'h2000  
)(
    input  wire                   aclk,
    input  wire                   aresetn,
    
    input  wire                   test_mode, // 1: 方波測試, 0: 原始資料

    // 上游介面 (來自 FIFO)
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,

    // 下游介面 (往 DAC)
    output wire [DATA_WIDTH-1:0]  m_axis_tdata,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready
);

    // --- 1. 1MHz 除法器控制 ---
    reg [6:0] clk_cnt;
    reg       is_high;

    always @(posedge aclk) begin
        if (!aresetn) begin
            clk_cnt <= 7'd0;
            is_high <= 1'b0;
        end else begin
            if (clk_cnt >= 7'd49) begin // 每 50 個週期翻轉，100MHz / 100 = 1MHz
                clk_cnt <= 7'd0;
                is_high <= ~is_high;
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end
        end
    end

    // --- 2. 依照 Python 格式打包數據 ---
    wire [13:0] s0_val;
    wire [13:0] s90_val;
    wire [31:0] test_data_packed;

    // 為了測試穩定度，我們讓 s0 和 s90 同步跳變
    assign s0_val  = is_high ? VAL_HIGH : VAL_LOW;
    assign s90_val = is_high ? VAL_HIGH : VAL_LOW;

    // 嚴格遵守：(s0 << 18) | (s90 << 2)
    assign test_data_packed = {s0_val, 2'b00, s90_val, 2'b00};

    // --- 3. AXIS 邏輯切換 ---
    assign m_axis_tdata  = (test_mode) ? test_data_packed : s_axis_tdata;
    assign m_axis_tvalid = (test_mode) ? 1'b1             : s_axis_tvalid;
    assign s_axis_tready = (test_mode) ? 1'b1             : m_axis_tready;

endmodule