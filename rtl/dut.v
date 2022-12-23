module MyDesign (
//---------------------------------------------------------------------------
//Control signals
  input   wire dut_run                    , 
  output  reg dut_busy                   ,
  input   wire reset_b                    ,  
  input   wire clk                        ,
 
//---------------------------------------------------------------------------
//Input SRAM interface
  output reg        input_sram_write_enable    ,
  output reg [11:0] input_sram_write_addresss  ,
  output reg [15:0] input_sram_write_data      ,
  output reg [11:0] input_sram_read_address    ,
  input wire [15:0] input_sram_read_data       ,

//---------------------------------------------------------------------------
//Output SRAM interface
  output reg        output_sram_write_enable    ,
  output reg [11:0] output_sram_write_addresss  ,
  output reg [15:0] output_sram_write_data      ,
  output reg [11:0] output_sram_read_address    ,
  input wire [15:0] output_sram_read_data       ,

//---------------------------------------------------------------------------
//Scratchpad SRAM interface
  output reg        scratchpad_sram_write_enable    ,
  output reg [11:0] scratchpad_sram_write_addresss  ,
  output reg [15:0] scratchpad_sram_write_data      ,
  output reg [11:0] scratchpad_sram_read_address    ,
  input wire [15:0] scratchpad_sram_read_data       ,

//---------------------------------------------------------------------------
//Weights SRAM interface                                                       
  output reg        weights_sram_write_enable    ,
  output reg [11:0] weights_sram_write_addresss  ,
  output reg [15:0] weights_sram_write_data      ,
  output reg [11:0] weights_sram_read_address    ,
  input wire [15:0] weights_sram_read_data       

//---------------------------------------------------------------------------


);

	reg [4:0]	state;	//FSM current state
  reg [3:0] locx; // x location for input data
  reg [3:0] locy; // y location for input data
  wire signed [7:0] input_data_0, input_data_1, weights_data_0, weights_data_1; // wire to allow for signed multiplication

  reg signed [7:0] kernel_mem [2:0][2:0]; // array storing kernel values
  reg signed [19:0] accumLeft; // left accumulator
  reg signed [19:0] accumRight; // right accumulator
 
  //Parameters
  localparam s0  = 3'b000;
  localparam s1  = 3'b001;
  localparam s2  = 3'b010;
  localparam s3  = 3'b011;
  localparam s4  = 3'b100;
  localparam s5  = 3'b101;
  localparam s6  = 3'b110;
  localparam s7  = 3'b111;
  localparam s8  = 4'b1000;
  localparam s9  = 4'b1001;
  localparam s10  = 4'b1010;
  localparam s11 = 4'b1011;
  localparam s12 = 4'b1100;
  localparam s13 = 4'b1101;
  localparam s14 = 4'b1110;
  localparam s15 = 4'b1111;
  localparam s16 = 5'b10000;

  // FSM

	always @(posedge clk) begin
		if (!reset_b)
			state = s0;
		else begin
      casex(state)
        s0 : begin // Initial state waiting for dut_run to go high
          dut_busy = 1'h0;
          weights_sram_read_address = 12'h0;
          input_sram_read_address = 12'h0;
          output_sram_write_addresss = 12'h0;
          output_sram_write_enable = 1'b0;
          if(dut_run) begin // dut_run goes high, start reading in kernel values to register
            dut_busy = 1'h1;
            state = s1;
            accumLeft = 20'b0;
            accumRight = 20'b0;
          end
        end
      // (s1-s5) read address into kernel mem, increment read address  
        s1 : begin   
          kernel_mem[0][0] = weights_data_1;
          kernel_mem[1][0] = weights_data_0;
          weights_sram_read_address = weights_sram_read_address + 12'b1;
          state = s2;
        end
        s2 : begin
          @(posedge clk);
          kernel_mem[2][0] = weights_data_1;
          kernel_mem[0][1] = weights_data_0;
          weights_sram_read_address = weights_sram_read_address + 12'b1;
          state = s3;
        end
        s3 : begin
          @(posedge clk);
          kernel_mem[1][1] = weights_data_1;
          kernel_mem[2][1] = weights_data_0;
          weights_sram_read_address = weights_sram_read_address + 12'b1;
          state = s4;
        end
        s4 : begin
          @(posedge clk);
          kernel_mem[0][2] = weights_data_1;
          kernel_mem[1][2] = weights_data_0;
          weights_sram_read_address = weights_sram_read_address + 12'b1;
          state = s5;
        end
        s5 : begin // last kernel read, set x and y locations for input reading to 0 before convolution
          @(posedge clk);
          kernel_mem[2][2] = weights_data_1;
          weights_sram_read_address = weights_sram_read_address + 12'b1;
          locx = 0;
          locy = 0;
          state = s6;
        end
        s6 : begin // check for end of SRAM
          if(locy < 14) begin // if not on last row (y location) to read for input SRAM
            state = s7;
          end
          else begin // on last row, go to finish state
            state = s16;
          end
        end
      // (s7-s12) using 3x4 window, perform two side by 3x3 convolutions and assign them to left accumulator and right accumulator
        s7 : begin 
          accumLeft = accumLeft + (input_data_1 * kernel_mem[0][0]) +(input_data_0 * kernel_mem[1][0]);
          accumRight = accumRight + (input_data_0 * kernel_mem[0][0]);
          input_sram_read_address = input_sram_read_address + 1;
          state = s8;
        end
        s8 : begin
          @(posedge clk);
          accumLeft = accumLeft + (input_data_1 * kernel_mem[2][0]);
          accumRight = accumRight + (input_data_1 * kernel_mem[1][0]) +(input_data_0 * kernel_mem[2][0]);
          input_sram_read_address = input_sram_read_address + 12'd7;
          
          state = s9;
        end
        s9 : begin
          @(posedge clk);
          accumLeft = accumLeft + (input_data_1 * kernel_mem[0][1]) +(input_data_0 * kernel_mem[1][1]);
          accumRight = accumRight + (input_data_0 * kernel_mem[0][1]);
          input_sram_read_address = input_sram_read_address + 1;
          state = s10;
        end
        s10 : begin
          @(posedge clk);
          accumLeft = accumLeft + (input_data_1 * kernel_mem[2][1]);
          accumRight = accumRight + (input_data_1 * kernel_mem[1][1]) +(input_data_0 * kernel_mem[2][1]);
          input_sram_read_address = input_sram_read_address + 12'd7;
          state = s11;
        end
        s11 : begin
          @(posedge clk);
          accumLeft = accumLeft + (input_data_1 * kernel_mem[0][2]) +(input_data_0 * kernel_mem[1][2]);
          accumRight = accumRight + (input_data_0 * kernel_mem[0][2]);
          input_sram_read_address = input_sram_read_address + 1;
          state = s12;
        end
        s12 : begin
          @(posedge clk);
          accumLeft = accumLeft + (input_data_1 * kernel_mem[2][2]);
          accumRight = accumRight + (input_data_1 * kernel_mem[1][2]) +(input_data_0 * kernel_mem[2][2]);
          output_sram_write_enable = 1'b1; // both multiplications finish, prepare output SRAM for writing 1 clock cycle prior
          state = s13;
        end
        s13 : begin // write accumulator data to output SRAM
        // ReLu Step
          output_sram_write_data[15:8] = (accumLeft  < 0 ? 'h0 : accumLeft > 20'd127 ? 8'd127 : accumLeft);
          output_sram_write_data[7:0] = (accumRight  < 0 ? 'h0 : accumRight > 20'd127 ? 8'd127 : accumRight);
          state = s14;
        end
        s14 : begin // increment write address, clear accumulators, set write enable low
          @(posedge clk);
          output_sram_write_addresss = output_sram_write_addresss + 1;
          accumLeft = 20'h0;
          accumRight = 20'h0;
          output_sram_write_enable = 1'b0;
          state = s15;
        end
        s15 : begin // check for last column (last x coord)
          if (locx < 6) begin // not at last column, move address up 2 rows and begin multiplication again, increment x value
            input_sram_read_address = input_sram_read_address - 12'd16;
            locx = locx + 1;
            state = s6;
          end
          else begin // at last column, move address to first value 1 row prior and begin multiplication again, increment y value as we are moving down 1 row, set x to 0 (new row)
            input_sram_read_address = input_sram_read_address - 12'd15;
            locx = 0;
            locy = locy + 1;
            state = s6;
          end
        end
        s16 : begin // convolution done
          dut_busy = 1'h0;
          state = s0;
        end
        default : begin // default state
          state = s0;
        end
      endcase
    end
	end

  // wires for signed multiplication

  assign input_data_0 = input_sram_read_data[7:0];
  assign input_data_1 = input_sram_read_data[15:8];
  assign weights_data_0 = weights_sram_read_data[7:0];
  assign weights_data_1 = weights_sram_read_data[15:8];
  
endmodule

