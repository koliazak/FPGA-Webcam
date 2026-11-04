// Parameters:
// DATA_WIDTH: The bit-width of each data word.
// ADDR_WIDTH: The number of address bits (determines ROM depth: 2^ADDR_WIDTH).
// INIT_FILE: The path to the file containing hexadecimal initialization data.

module dual_port_rom #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 6,
    parameter INIT_FILE  = "rom_init.txt"
) (
    input wire                      clk,    // Single clock signal for both ports
    
    // Port A Interface
    input wire [ADDR_WIDTH-1:0]     addr_a, // Address for Port A
    output reg [DATA_WIDTH-1:0]     q_a,    // Data output from Port A
    
    // Port B Interface
    input wire [ADDR_WIDTH-1:0]     addr_b, // Address for Port B
    output reg [DATA_WIDTH-1:0]     q_b     // Data output from Port B
);

    reg [DATA_WIDTH-1:0] rom [2**ADDR_WIDTH-1:0];

    initial begin
        $readmemh(INIT_FILE, rom);
    end

    // Port A: Synchronous Read
    always @(posedge clk) begin
        q_a <= rom[addr_a];
    end

    // Port B: Synchronous Read
    always @(posedge clk) begin
        q_b <= rom[addr_b];
    end

endmodule
