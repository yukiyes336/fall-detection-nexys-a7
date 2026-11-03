`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/29 19:10:47
// Design Name: 
// Module Name: uart_tx
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


module uart_tx(
    input wire clk,
    input wire rst_n,
    input wire [7:0] tx_data,
    input wire tx_start,
    output reg tx,
    output reg tx_done
    );
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;
    reg [9:0] baud_cnt;
    wire bit_done;
    reg [1:0] state;
    reg [2:0] bit_cnt;
    reg start_clear;
    reg start_first;
    //波特率
    always@(posedge clk or negedge rst_n)begin
        if(rst_n==0||start_clear)begin
            baud_cnt<=0;
        end else if(baud_cnt==10'd867)begin
            baud_cnt<=0;
        end else 
            baud_cnt<=baud_cnt+1;
    end
    assign bit_done=(baud_cnt==10'd867);  
    //状态机  
    always@(posedge clk or negedge rst_n)begin
        if(rst_n==0)begin
            state<=IDLE;
            bit_cnt<=0;
            tx<=1;
            tx_done<=0;
            start_clear<=0;
        end else begin
            tx_done<=0;
            case(state)
                IDLE:begin
                    tx<=1;
                    if(tx_start)begin
                        state<=START;
                        bit_cnt<=0;
                        start_clear<=1;
                        start_first<=1;
                    end
                end
                START:begin
                    tx<=0;
                    start_clear<=0;
                    if(start_first)begin
                        start_first<=0;
                    end else
                        if(bit_done)
                            state<=DATA;
                end
                DATA:begin
                    tx<=tx_data[bit_cnt];
                    if(bit_done)begin
                        if(bit_cnt==3'd7)begin
                            state<=STOP;
                        end else begin
                            bit_cnt<=bit_cnt+1;
                        end
                    end
                end
                STOP:begin
                    tx<=1;
                    if(bit_done)begin
                        state<=IDLE;
                        tx_done<=1;
                    end
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
