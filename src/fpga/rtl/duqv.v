`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/23 19:32:35
// Design Name: 
// Module Name: i2c_master
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


module i2c_master(
    input wire clk,
    input wire rst_n,
    output reg scl,
    inout wire sda,
    input wire rw,
    input wire [7:0] reg_addr,
    input wire start_en,
    output reg [7:0] rx_byte,
    output reg done,
    output reg byte_done,
    input wire [7:0] data_write
    );
    localparam IDLE=4'd0;
    localparam START=4'd1;
    localparam SEND_BYTE=4'd2;
    localparam WAIT_ACK=4'd3;
    localparam REPEATED_START = 4'd4;
    localparam READ_BYTE=4'd5;
    localparam SEND_ACK=4'd6;
    localparam STOP=4'd7;
    localparam START_HOLD = 4'd8;
    localparam ACK_HOLD = 4'd9;
    localparam WAIT_ACK_PREP = 4'd10;
    localparam STOP_PREP = 4'd11;
    localparam NACK_HOLD = 4'd12;
    reg [8:0] cnt;
    reg [3:0] state;
    reg sda_out;
    reg sda_oe;
    reg [3:0] bit_cnt;
    reg [3:0] byte_cnt;
    reg [7:0]tx_byte;
    reg scl_prev;
    wire scl_falling;
    wire scl_rising;
    reg [1:0] tx_state;
    reg start_en_latched;
    reg read_first;
    //所存start_en
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            start_en_latched <= 0;
        else if (start_en)
            start_en_latched <= 1;    
        else if (state == START)
            start_en_latched <= 0;    
    end
    //时钟分频
    always @(posedge clk or negedge rst_n)begin
        if(rst_n==0)begin
            scl<=1;
            cnt<=0;
            end else if (state == IDLE)begin
                scl<=1;
                cnt<=0;
             end
             else if(cnt==9'd499)begin
                scl<=~scl;
                cnt<=0;
             end else
                cnt<=cnt+1;
        end
    //初始化sda和scl_falling
    assign sda=sda_oe ? sda_out:1'bz;
    always @(posedge clk or negedge rst_n) begin
        if (rst_n==0)
            scl_prev <= 0;
        else
            scl_prev <= scl;
    end
    assign scl_falling = (scl_prev == 1 && scl == 0);
    assign scl_rising = (scl_prev == 0 && scl == 1);
    //状态机
    always @(posedge clk or negedge rst_n)begin
        if(rst_n==0)begin
            state<=IDLE;
            bit_cnt<=3'd7;
            sda_oe<=0;
            done<=0;
            byte_done<=0;
            end else begin
                byte_done<=0;
                case(state)
                    IDLE:begin
                        tx_state<=2'd0;
                        byte_cnt<=0;
                        done<=0;
                        sda_oe<=0;
                        if(start_en_latched)
                        state<=START;
                    end
                    START:begin
                         if(scl==1&&sda==1)begin
                             tx_byte<=8'b11010000;
                             sda_oe<=1;
                             sda_out<=0;
                             bit_cnt<=3'd7;
                             state<=START_HOLD;
                         end
                    end
                    START_HOLD: begin
                        if (scl_falling) begin
                        if (tx_byte[bit_cnt] == 1'b0) begin
                            sda_oe  <= 1'b1;
                            sda_out <= 1'b0;
                        end else begin
                            sda_oe <= 1'b0;
                        end
                        bit_cnt <= bit_cnt - 1'b1;
                        state   <= SEND_BYTE;
                        end
                    end
                    SEND_BYTE:begin
                        if(scl_falling)begin
                           if(tx_byte[bit_cnt]==0)begin
                            sda_oe<=1;
                            sda_out<=0;
                           end else 
                            sda_oe<=0;
                           if(bit_cnt==3'd0)begin
                            state<= WAIT_ACK_PREP;
                            bit_cnt<=3'd7;
                           end else 
                                bit_cnt<=bit_cnt-1;
                       end
                    end
                    WAIT_ACK_PREP: begin
                        if (scl_falling) begin
                            sda_oe <= 1'b0;
                            state  <= WAIT_ACK;
                        end
                    end
                    WAIT_ACK:begin
                        sda_oe<=0;
                        if(scl==1)begin
                            if(sda==0)begin
                                case(tx_state)
                                    2'd0:begin
                                        tx_byte<=reg_addr;
                                        tx_state<=2'd1;
                                        bit_cnt<=3'd7;
                                        state<=SEND_BYTE;
                                    end
                                    2'd1:begin
                                        if(rw==0)begin
                                            tx_byte<=data_write;
                                            tx_state<=2'd2;
                                            bit_cnt<=3'd7;
                                            state<=SEND_BYTE;
                                        end else begin
                                            tx_state<=2'd3;
                                            state<=REPEATED_START;
                                        end
                                    end
                                    2'd2:begin
                                        state<=STOP_PREP;
                                    end
                                    2'd3:begin
                                        byte_cnt<=4'd0;
                                        read_first<=0;
                                        sda_oe<=0;
                                        state<=READ_BYTE;
                                    end
                                    default: state <= IDLE;
                                endcase
                            end
                        end
                    end
                    REPEATED_START:begin
                        if(scl_falling)
                        sda_oe<=0;
                        if(scl==1&&sda==1)begin
                            sda_oe<=1;
                            sda_out<=0;
                            tx_byte<=8'b11010001;
                            bit_cnt<=3'd7;
                            state<=SEND_BYTE;
                        end
                    end
                    READ_BYTE:begin
                        sda_oe<=0;
                        if(scl_rising)
                            read_first<=1;
                        if(scl==1&&read_first)begin
                           rx_byte[bit_cnt]<=sda;
                           read_first<=0;
                           if(bit_cnt==0)begin
                            byte_done <=1;
                            state<=SEND_ACK;
                            bit_cnt<=3'd7;
                            end else 
                                bit_cnt<=bit_cnt-1;
                        end
                    end
                    SEND_ACK:begin
                       if(scl_falling)begin
                        if(byte_cnt==4'd13)begin
                            sda_oe<=0;
                            byte_cnt<=4'd0;
                            state<=NACK_HOLD;
                        end else begin
                            sda_oe<=1;
                            sda_out<=0;
                            byte_cnt<=byte_cnt+1;
                            state<=ACK_HOLD;
                        end
                       end
                    end
                    ACK_HOLD: begin
                        if(scl_falling)begin
                        state <= READ_BYTE;
                        sda_oe<=0;
                        end
                    end
                    NACK_HOLD: begin
                        if (scl_falling) begin
                            sda_oe  <= 1'b1;
                            sda_out <= 1'b0;
                            state   <= STOP;
                        end
                    end
                    STOP_PREP: begin
                        if (scl_falling) begin
                            sda_oe  <= 1'b1;
                            sda_out <= 1'b0;
                            state   <= STOP;
                        end
                    end
                    STOP: begin
                        if (scl_rising) begin
                            sda_oe <= 1'b0;
                            state  <= IDLE;
                            done   <= 1'b1;
                        end
                    end
                    default:state<=IDLE;
                endcase
            end
        end 
endmodule
