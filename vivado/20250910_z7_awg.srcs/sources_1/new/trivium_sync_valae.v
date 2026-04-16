`timescale 1ns / 1ps

module trivium_sync_valve (
    input  wire clk,
    input  wire resetn,
    input  wire hw_trigger_in,

    // 只留一組，保證 Block Design 乾乾淨淨
    input  wire [31:0] s0_axis_tdata,
    input  wire        s0_axis_tvalid,
    output wire        s0_axis_tready,
    output wire [31:0] m0_axis_tdata,
    output wire        m0_axis_tvalid,
    input  wire        m0_axis_tready
);

    reg trig_m1, trig_sync;

    always @(posedge clk) begin
        if (!resetn) begin
            trig_m1 <= 0;
            trig_sync <= 0;
        end else begin
            trig_m1 <= hw_trigger_in;
            trig_sync <= trig_m1; 
        end
    end

    assign s0_axis_tready = trig_sync ? m0_axis_tready : 1'b0;
    assign m0_axis_tvalid = trig_sync ? s0_axis_tvalid : 1'b0;
    assign m0_axis_tdata  = s0_axis_tdata;

endmodule