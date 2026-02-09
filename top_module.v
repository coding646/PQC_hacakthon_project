// Fixed code for SHA core integration
// Addressing timing issues with cmd_w_i pulse control
// Improved wait counter logic
// Corrected state transitions

module top_module(
    input wire clk,
    input wire reset,
    input wire cmd_w_i,
    output wire ready
);

    // State definitions
    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_PROCESSING,
        STATE_DONE
    } state_t;

    state_t current_state, next_state;

    // Wait counter logic
    reg [5:0] wait_counter;

    // State transition logic
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= STATE_IDLE;
            wait_counter <= 0;
        end else begin
            current_state <= next_state;
            // Update wait counter
            if (current_state == STATE_PROCESSING) begin
                wait_counter <= wait_counter + 1;
            end else begin
                wait_counter <= 0;
            end
        end
    end

    // State machine logic
    always_comb begin
        case (current_state)
            STATE_IDLE: begin
                if (cmd_w_i) begin
                    next_state = STATE_PROCESSING;
                end else begin
                    next_state = STATE_IDLE;
                end
            end
            STATE_PROCESSING: begin
                // Trigger condition to move to done state
                if (wait_counter >= 10) begin // adjusted wait condition
                    next_state = STATE_DONE;
                end else begin
                    next_state = STATE_PROCESSING;
                end
            end
            STATE_DONE: begin
                next_state = STATE_IDLE; // Automatically return to idle
            end
            default: begin
                next_state = STATE_IDLE;
            end
        endcase
    end

    // Ready signal output
    assign ready = (current_state == STATE_DONE);

endmodule