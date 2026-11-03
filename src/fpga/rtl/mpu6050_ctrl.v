`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/02 10:14:33
// Design Name: 
// Module Name: mpu6050_ctrl
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module mpu6050_ctrl(
    input wire clk,
    input wire rst_n,
    output reg start_en,
    output reg rw,
    output reg [7:0] reg_addr,
    output reg [7:0] data_write,
    input wire done
    );
    localparam POWER_ON      =5'd0;
    localparam SOFT_RESET    =5'd1;
    localparam WAIT_RST      =5'd2;
    localparam RST_DELAY     =5'd3;
    localparam INIT_6B       =5'd4;
    localparam WAIT_1        =5'd5;
    localparam WAIT_6B       =5'd6;
    localparam INIT_1C       =5'd7;
    localparam WAIT_2        =5'd8;
    localparam WAIT_1C       =5'd9;
    localparam INIT_6C       =5'd10;   // 写 0x6C = 0x00
    localparam WAIT_6C       =5'd11;
    localparam WAIT_6C_STABLE=5'd12;   // 配置后等 10ms
    localparam STABLE        =5'd13;   // 稳定 200ms
    localparam READ          =5'd14;
    localparam WAIT_3        =5'd15;
    localparam DELAY         =5'd16;
    reg [4:0] state;
    reg [25:0] delay_cnt;
    always@(posedge clk or negedge rst_n)begin
        if(rst_n==0)begin
            state<=POWER_ON;
            delay_cnt<=0;
            start_en<=0;
            rw<=0;
            reg_addr<=8'b01101011;
            data_write<=8'b00000000;
        end else begin 
            case(state)
                POWER_ON:begin
                    if(delay_cnt==26'd9999999)begin
                        delay_cnt<=0;
                        state<=SOFT_RESET;
                    end else begin
                        delay_cnt<=delay_cnt+1;
                    end
                end
                SOFT_RESET:begin
                    start_en   <= 1;
                    rw         <= 0;
                    reg_addr   <= 8'h6B;
                    data_write <= 8'h80;
                    state      <= WAIT_RST;
                end
                WAIT_RST: begin
                    start_en <= 0;
                    if (done) begin
                        delay_cnt <= 0;
                        state     <= RST_DELAY;
                    end
                end
                RST_DELAY: begin
                    if (delay_cnt == 26'd9_999_999) begin
                        delay_cnt <= 0;
                        state     <= INIT_6B;
                    end else
                        delay_cnt <= delay_cnt + 1;
                end
                INIT_6B:begin
                    start_en<=1;
                    rw         <= 0;
                    reg_addr   <= 8'h6B;
                    data_write <= 8'h00;
                    state<=WAIT_1;
                end
                WAIT_1:begin
                    start_en<=0;
                    if(done)begin
                        delay_cnt<=0;
                        reg_addr<=8'b00011100;
                        data_write<=8'b00010000;
                        state<=WAIT_6B;
                    end
                end
                WAIT_6B:begin
                    if(delay_cnt==26'd4999999)begin
                        delay_cnt<=0;
                        state<=INIT_1C;
                    end else begin
                        delay_cnt<=delay_cnt+1;
                    end
                end
                INIT_1C:begin
                    start_en<=1;
                    state<=WAIT_2;
                    rw<=0;
                end
                WAIT_2:begin
                    start_en<=0;
                    if(done)begin
                        rw<=1;
                        delay_cnt<=0;
                        state<=WAIT_1C;
                        reg_addr<=8'b00111011;
                    end
                end
                WAIT_1C:begin
                    if(delay_cnt==26'd19999999)begin
                        delay_cnt<=0;
                        state<=INIT_6C;
                    end else begin
                        delay_cnt<=delay_cnt+1;
                    end
                end
                // ===== 6. 写 0x6C = 0x00（使能所有轴）=====
                INIT_6C: begin
                    start_en   <= 1;
                    rw         <= 0;
                    reg_addr   <= 8'h6C;
                    data_write <= 8'h00;
                    state      <= WAIT_6C;
                end
                WAIT_6C: begin
                    start_en <= 0;
                    if (done) begin
                        delay_cnt <= 0;
                        state     <= WAIT_6C_STABLE;
                    end
                end
                WAIT_6C_STABLE: begin
                    if (delay_cnt == 26'd999_999) begin
                        delay_cnt <= 0;
                        state     <= STABLE;
                    end else
                        delay_cnt <= delay_cnt + 1;
                end
                // ===== 7. 稳定 200ms =====
                STABLE: begin
                    if (delay_cnt == 26'd19_999_999) begin
                        delay_cnt <= 0;
                        state     <= READ;
                    end else
                        delay_cnt <= delay_cnt + 1;
                end
                READ:begin
                    start_en<=1;
                    rw       <= 1;
                    reg_addr <= 8'h3B;
                    state<=WAIT_3;
                end
                WAIT_3:begin
                    start_en<=0;
                    if(done)begin
                        state<=DELAY;
                        delay_cnt<=0;
                    end
                end
                DELAY:begin
                    if(delay_cnt==26'd1999999)begin
                        state<=READ;
                        delay_cnt<=0;
                    end else
                        delay_cnt<=delay_cnt+1;
                end
                default:state<=POWER_ON;
            endcase
        end
    end
endmodule
