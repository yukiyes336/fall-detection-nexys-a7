`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/05 10:05:08
// Design Name: 
// Module Name: top
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


module top(
    input wire clk,
    input wire rst_n,
    output wire scl,
    inout wire sda,
    output wire tx
    );
    wire start_en;
    wire rw;
    wire [7:0] reg_addr;
    wire [7:0] rx_byte;
    wire done;
    wire [7:0] tx_data;
    wire tx_start;
    wire [7:0] data_write;
    wire byte_done;
    wire tx_done;
    i2c_master u_i2c(
        .clk (clk),
        .rst_n (rst_n),
        .start_en (start_en),
        .rw (rw),
        .reg_addr (reg_addr),
        .rx_byte (rx_byte),
        .done (done),
        .scl (scl),
        .sda (sda),
        .byte_done (byte_done),
        .data_write (data_write)
    );
    uart_tx u_uart(
        .clk (clk),
        .rst_n (rst_n),
        .tx_data (tx_data),
        .tx_start (tx_start),
        .tx (tx),
        .tx_done (tx_done)
    );
    mpu6050_ctrl u_mpu6050(
        .clk (clk),
        .rst_n (rst_n),
        .start_en (start_en),
        .rw (rw),
        .reg_addr (reg_addr),
        .data_write (data_write),
        .done (done)
    );
    data_pack u_pack(
        .clk (clk),
        .rst_n (rst_n),
        .byte_done (byte_done),
        .tx_done (tx_done),
        .rx_byte (rx_byte),
        .tx_start (tx_start),
        .tx_data (tx_data)
    );
endmodule
