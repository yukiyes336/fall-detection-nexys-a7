`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/05 11:07:02
// Design Name: 
// Module Name: data_pack
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


module data_pack(
    input wire clk,
    input wire rst_n,
    input wire byte_done,
    input wire tx_done,
    input wire [7:0] rx_byte,
    output reg tx_start,
    output reg [7:0] tx_data
    );
    localparam IDLE=2'd0;
    localparam RECEIVE=2'd1;
    localparam SEND=2'd2;
    reg [1:0] state;
    reg [3:0] rece_cnt;
    reg [4:0] send_cnt;
    reg [7:0] data_buf [0:13];
    always@(posedge clk or negedge rst_n)begin
        if(rst_n==0)begin
            state<=IDLE;
            rece_cnt<=0;
            send_cnt<=0;
            tx_start<=0;
            tx_data<=0;
        end else begin
            case(state)
                IDLE:begin
                    tx_start<=0;
                    rece_cnt<=0;
                    send_cnt<=0;
                    if(byte_done)begin
                        data_buf[0]<=rx_byte;
                        rece_cnt<=4'd1;
                        state<=RECEIVE;
                    end
                end
                RECEIVE:begin
                    if(byte_done)begin
                        data_buf[rece_cnt]<=rx_byte;
                        if(rece_cnt==4'd13)begin
                            send_cnt<=0;
                            state<=SEND;
                        end else 
                        rece_cnt<=rece_cnt+1;
                    end
                end
                SEND:begin
                    if(tx_done)begin
                        if(send_cnt==5'd17)begin
                            tx_start<=1;
                            tx_data<=8'hDD;
                            state<=IDLE;
                        end else begin
                            tx_start<=1;
                            send_cnt<=send_cnt+1;
                            case(send_cnt)
                                5'd0:tx_data<=8'hAA;
                                5'd1:tx_data<=8'hBB;
                                5'd2:tx_data<=data_buf[0];
                                5'd3:tx_data<=data_buf[1];
                                5'd4:tx_data<=data_buf[2];
                                5'd5:tx_data<=data_buf[3];
                                5'd6:tx_data<=data_buf[4];
                                5'd7:tx_data<=data_buf[5];
                                5'd8:tx_data<=data_buf[6];
                                5'd9:tx_data<=data_buf[7];
                                5'd10:tx_data<=data_buf[8];
                                5'd11:tx_data<=data_buf[9];
                                5'd12:tx_data<=data_buf[10];
                                5'd13:tx_data<=data_buf[11];
                                5'd14:tx_data<=data_buf[12];
                                5'd15:tx_data<=data_buf[13];
                                5'd16:tx_data<=8'hCC;
                                default:tx_data<=0;
                            endcase
                        end
                    end else begin
                        tx_start<=0;
                    end
                    if(send_cnt==0)begin
                        tx_start<=1;
                        tx_data<=8'hAA;
                        send_cnt<=send_cnt+1;
                    end
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
