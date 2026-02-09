
module top_module(clk, reset_n, uart_rxd, uart_txd);
input  clk;
input  reset_n; // active-low
input  uart_rxd;
output uart_txd;

// Internal signals for UART and SHA control
wire        uart_rx_valid;
wire [7:0]  uart_rx_data;
wire        uart_rx_break;
reg         uart_rx_en;

wire        uart_tx_busy;
reg         uart_tx_en;
reg  [7:0]  uart_tx_data;

// SHA interface signals (sha256 expects 32-bit words and active-high reset)
reg  [31:0] text_i;
wire [31:0] text_o;
reg  [2:0]  cmd_i;
reg         cmd_w_i;
wire [3:0]  cmd_o;

reg [511:0] message_buffer;
reg [255:0] hash_buffer;

reg [5:0] rx_count;         // 0..63
reg [3:0] sha_write_cnt;    // 0..15
reg [2:0] sha_read_cnt;     // 0..7
reg [4:0] tx_count;         // 0..31

//FSM States
reg [2:0] state;
reg [2:0] next_state;

localparam S_IDLE      = 0;
localparam S_RX        = 1;
localparam S_SHA_WRITE = 2;
localparam S_SHA_WAIT  = 3;
localparam S_SHA_READ  = 4;
localparam S_TX        = 5;

// Next-state logic (combinational)
always @(*) begin
    case(state)
        S_IDLE:
            next_state = uart_rx_valid ? S_RX : S_IDLE;

        S_RX:
            next_state = (rx_count == 6'd63) ? S_SHA_WRITE : S_RX;

        S_SHA_WRITE:
            next_state = (sha_write_cnt == 4'd15) ? S_SHA_WAIT : S_SHA_WRITE;

        S_SHA_WAIT:
            next_state = (cmd_o[3] == 1'b0) ? S_SHA_READ : S_SHA_WAIT;

        S_SHA_READ:
            next_state = (sha_read_cnt == 3'd7) ? S_TX : S_SHA_READ;

        S_TX:
            next_state = (tx_count == 5'd31) ? S_IDLE : S_TX;

        default:
            next_state = S_IDLE;
    endcase
end


// Sequential: main control registers and outputs
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        rx_count        <= 6'd0;
        sha_write_cnt   <= 4'd0;
        sha_read_cnt    <= 3'd0;
        tx_count        <= 5'd0;
        uart_tx_en      <= 1'b0;
        cmd_w_i         <= 1'b0;
        cmd_i           <= 3'b000;
        text_i          <= 32'd0;
        message_buffer  <= 512'd0;
        hash_buffer     <= 256'd0;
        state           <= S_IDLE;
        uart_rx_en      <= 1'b1;
    end
    else begin

        // Default outputs/controls
        uart_tx_en <= 1'b0;
        cmd_w_i    <= 1'b0;

        case(state)

        // -----------------------
        S_IDLE: begin
            rx_count      <= 6'd0;
            sha_write_cnt <= 4'd0;
            sha_read_cnt  <= 3'd0;
            tx_count      <= 5'd0;
        end

        // -----------------------
        S_RX: begin
            // Receiver already enabled from reset; accumulate bytes
            if (uart_rx_valid) begin
                message_buffer <= {message_buffer[503:0], uart_rx_data};
                rx_count <= rx_count + 1'b1;
            end
        end

        // -----------------------
        S_SHA_WRITE: begin
            // Provide 32-bit words to sha256, MSB-first chunking as original code intended
            text_i   <= message_buffer[511 - sha_write_cnt*32 -: 32];
            cmd_i    <= 3'b010; // write
            cmd_w_i  <= 1'b1;

            sha_write_cnt <= sha_write_cnt + 1'b1;
        end

        // -----------------------
        S_SHA_READ: begin
            cmd_i   <= 3'b001; // read
            cmd_w_i <= 1'b1;

            hash_buffer <= {hash_buffer[223:0], text_o};
            sha_read_cnt <= sha_read_cnt + 1'b1;
        end

        // -----------------------
        S_TX: begin
            if (!uart_tx_busy) begin
                uart_tx_data <= hash_buffer[255 - tx_count*8 -: 8];
                uart_tx_en   <= 1'b1;
                tx_count     <= tx_count + 1'b1;
            end
        end

        endcase

        // advance FSM state
        state <= next_state;
    end
end

// Instantiate UART transmitter
uart_tx uart_tx_inst(
    .clk(clk),
    .resetn(reset_n),
    .uart_txd(uart_txd),
    .uart_tx_busy(uart_tx_busy),
    .uart_tx_en(uart_tx_en),
    .uart_tx_data(uart_tx_data)
);

// Instantiate UART receiver
uart_rx uart_rx_inst(
    .clk(clk),
    .resetn(reset_n),
    .uart_rxd(uart_rxd),
    .uart_rx_en(uart_rx_en),
    .uart_rx_break(uart_rx_break),
    .uart_rx_valid(uart_rx_valid),
    .uart_rx_data(uart_rx_data)
);

// Instantiate SHA-256 core (note: core uses active-high reset)
sha256 sha256_inst(
    .clk_i(clk),
    .rst_i(~reset_n),
    .text_i(text_i),
    .text_o(text_o),
    .cmd_i(cmd_i),
    .cmd_w_i(cmd_w_i),
    .cmd_o(cmd_o)
);

endmodule
