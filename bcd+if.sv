interface bcd_if ();
	logic [9:0] if_binary;
	logic [3:0] if_hundreds;
	logic [3:0] if_tens;
	logic [3:0] if_ones;
	//logic if_ready;

	modport mp_drv( 
		output if_binary
	);  

	modport mp_mon(
		input if_binary, if_hundreds, if_tens, if_ones
	);

endinterface: bcd_if

module bcd (
//	input [7:0] binary,
	input  [9:0] binary,
	output logic [3:0] hundreds,
	output logic [3:0] tens,
	output logic [3:0] ones
	//output logic output_ready
);
	
	integer i;
	
	always @(binary) begin

		// new input received, set ready to 0
		//output_ready = 0;
		// set 100's, 10's, and 1's to zero
		hundreds = 4'd0;
		tens = 4'd0;
		ones = 4'd0;

//		for (i=7; i>=0; i=i-1) begin
		for (i=9; i>=0; i=i-1) begin
			// add 3 to columns >= 5
			if (hundreds >= 5)
				hundreds = hundreds + 3;
			if (tens >= 5)
				tens = tens + 3;
			if (ones >= 5)
				ones = ones + 3;
				
			// shift left one
			hundreds = hundreds << 1;
			hundreds[0] = tens[3];
			tens = tens << 1;
			tens[0] = ones[3];
			ones = ones << 1;
			ones[0] = binary[i];
		end

		// Output ready / stable for read out
		//output_ready = 1;
	end
endmodule
