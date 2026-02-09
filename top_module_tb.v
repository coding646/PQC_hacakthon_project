`timescale 1ns/1ps

module top_module_tb;

reg clk = 0;
reg reset_n = 0;
reg uart_rxd = 1'b1;
wire uart_txd;

// Instantiate DUT
top_module uut (
    .clk(clk),
    .reset_n(reset_n),
    .uart_rxd(uart_rxd),
    .uart_txd(uart_txd)
);

// 50 MHz clock (20 ns period)
always #10 clk = ~clk;

// UART parameters
localparam CYCLES_PER_BIT = 5208;  // (1e9 / 9600) / 20ns

// Task to send a UART byte over uart_rxd
// Baud rate 9600, clock 50MHz => cycles per bit = ~5208
task send_uart_byte;
    input [7:0] data;
    integer bit_idx;
    begin
        // Start bit (0)
        uart_rxd = 1'b0;
        repeat (CYCLES_PER_BIT) @(posedge clk);
        
        // Data bits (LSB first)
        for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
            uart_rxd = data[bit_idx];
            repeat (CYCLES_PER_BIT) @(posedge clk);
        end
        
        // Stop bit (1)
        uart_rxd = 1'b1;
        repeat (CYCLES_PER_BIT) @(posedge clk);
    end
endtask

integer i;
integer timeout;
integer prev_state;

initial begin
    // Pulse reset
    reset_n = 1'b0;
    repeat (10) @(posedge clk);
    reset_n = 1'b1;
    @(posedge clk);

    $display("[INFO] Starting UART reception of 64 bytes...");

    // Send 64 bytes (0x00 to 0x3F) via UART
    for (i = 0; i < 64; i = i + 1) begin
        send_uart_byte(i[7:0]);
        if ((i + 1) % 16 == 0) begin
            $display("[INFO] Sent %0d bytes", i + 1);
        end
    end

    $display("[INFO] All bytes sent. Waiting for DUT to process...");

    // Wait for DUT to finish processing and reach idle
    prev_state = -1;
    timeout = 0;
    while (uut.state != 3'd0 && timeout < 10000000) begin
        // Log state transitions
        if (uut.state != prev_state) begin
            $display("[TRANS@%0d] state %0d->%0d, rx=%0d, sha_w=%0d, sha_r=%0d, tx=%0d", 
                     timeout, prev_state, uut.state, uut.rx_count, uut.sha_write_cnt, uut.sha_read_cnt, uut.tx_count);
            prev_state = uut.state;
        end
        
        // Log every 50k cycles
        if (timeout % 50000 == 0) begin
            $display("[%0d] state=%0d, rx=%0d, sha_w=%0d, sha_r=%0d, tx=%0d, rx_valid=%b, busy=%b", 
                     timeout, uut.state, uut.rx_count, uut.sha_write_cnt, uut.sha_read_cnt, uut.tx_count,
                     uut.uart_rx_valid, uut.sha256_inst.cmd_o[3]);
        end
        
        @(posedge clk);
        timeout = timeout + 1;
    end

    if (timeout >= 10000000) begin
        $display("[FAIL] Timeout. Final state=%0d", uut.state);
        $finish;
    end

    $display("[INFO] Processing complete. All states cycled.");
    $display("[DEBUG] Final: hash_buffer=0x%08x (top 32 bits)", uut.hash_buffer[255:224]);

    if (uut.hash_buffer == 256'd0) begin
        $display("[WARN] hash_buffer is zero.");
    end else begin
        $display("[PASS] hash_buffer non-zero");
    end

    $display("[INFO] Testbench simulation complete.");
    $finish;
end

endmodule
