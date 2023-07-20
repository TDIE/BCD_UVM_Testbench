// UVM Test Bench for binary to BCD converter (Double Dabble)
// Author: Tom Diederen
// Date: June 2023
// Skill development project. Not meant for other use cases.

`include "uvm_macros.svh"

import uvm_pkg::*;


//Agent Configuration.
//  Driver and Monitor BFMs (virtual interfaces)
//  Active vs Passive option
//  has_functional coverage switch
class bcd_agent_config extends uvm_object;
	//Register with UVM Factory
	`uvm_object_utils(bcd_agent_config)

	//BFM Virtual Interfaces
	virtual bcd_if mon_bfm;
	virtual bcd_if drv_bfm;	

	//Agent configuration options
	uvm_active_passive_enum active = UVM_ACTIVE;
	bit has_functional_coverage = 0;

	//Constructor
	function new(string name = "bcd_agent_config");
		super.new(name);
	endfunction

endclass: bcd_agent_config 

//Environment Configuration
//  Driver and Monitor BFMs (virtual interfaces)
//	has_functional_coverage, has_scoreboard
//  bcd_agent_config
class env_config extends uvm_object;
	//Register with UVM Factory
	`uvm_object_utils(env_config);

	//BFM Virtual Interfaces
	virtual bcd_if bcd_mon_bfm;
	virtual bcd_if bcd_driv_bfm;

	//Environment configuration options	
	bit has_functional_coverage = 0;
	bit has_scoreboard = 1;

	//Configurations for the sub_component(s)
	bcd_agent_config m_bcd_agent_cfg;
	

	function new(string name="env_config");
		super.new(name);
	endfunction

endclass

// BCD "Transaction"
//   Randomizable 10 bit input: binary
//   4 bit outputs: hundreds, tens, ones
//   Convert to string function: convert2str()
//   Constraints: one_bit_only, ls_nibble_only
class bcd_txn extends uvm_sequence_item;
	//Register with UVM Factory
	`uvm_object_utils(bcd_txn)

	rand bit[9:0] binary;
	bit[3:0] hundreds;
	bit[3:0] tens;
	bit[3:0] ones;

	function string convert2str();
		return $sformatf("binary= %b hundreds= %b tens= %b ones= %b", binary, hundreds, tens, ones);
	endfunction

	function new(string name="bcd_txn");
		super.new(name);
	endfunction

	//one bit only
	//constraint one_bit_only {binary <= 9'b0_0000_0001;}

	//Nibble (leas significant)
	//constraint ls_nibble_only {binary <= 9'b0_0000_1111;}


endclass: bcd_txn

//Base Sequence
//  sends sequence item seq_item n_times.
class base_sequence extends uvm_sequence #(bcd_txn);
	//Register with UVM Factory
	`uvm_object_utils(base_sequence)

	bcd_txn seq_item;
	int n_times = 1023;

	//Construnctor
	function new (string name="base_sequence");
		super.new(name);
	endfunction

	task body();
		//Raise objection
		if (starting_phase != null) begin
			starting_phase.raise_objection(this);
		end
		
		seq_item = bcd_txn::type_id::create("seq_item");
		
		//Send a sequence item "n_times"
		for (int i = 0; i < n_times; i++) begin
			start_item(seq_item);
			seq_item.binary = i; 
			//`uvm_info("body", $sformatf("Sequence item: %b", seq_item.binary), UVM_LOW) 
			finish_item(seq_item);
		end

		//Drop objection
		if (starting_phase != null) begin
			starting_phase.drop_objection(this);
		end
	endtask

endclass: base_sequence

// UVM Driver
//   Obtains binary value from sequence item and sends it to the binary input port of the DUT through the interface
class bcd_driver extends uvm_driver #(bcd_txn);
	//Register with UVM Factory
	`uvm_component_utils(bcd_driver)

	//Constructor
	function new(string name="bcd_driver", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	//Virtual interface handle
	virtual bcd_if m_bfm;

	//Run Phase
	task run_phase(uvm_phase phase);
		bcd_txn item; 

		forever begin
			//`uvm_info(get_type_name(), $sformatf("Driver run phase started"), UVM_LOW);
			seq_item_port.get_next_item(item);
			`uvm_info(get_type_name(), $sformatf("Driver received sequence item. Binary: %b", item.binary), UVM_LOW);
			m_bfm.if_binary = item.binary;			
			seq_item_port.item_done(); 

		end
	endtask: run_phase

endclass: bcd_driver

// UVM Monitor
//   Captures bcd output values, i.e. 'hundreds', 'tens', and 'ones' from the DUT in a sequence items
//   Also captures the binary input that created the output in the same sequence item
class bcd_monitor extends uvm_monitor;
	//Register with UVM Factory
	`uvm_component_utils(bcd_monitor)

	uvm_analysis_port #(bcd_txn) bcd_mon_ap; //Analysis port
	virtual bcd_if m_bfm; //BFM handle (virtual interface to DUT)
	bcd_agent_config m_config; //Config, contains monitor BFM handle
	bcd_txn item; //Sequence item

	//Constructor
	function new(string name="bcd_monitor", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	//Build Phase 
	function void build_phase(uvm_phase phase);
		bcd_mon_ap = new("bcd_mon_ap", this); //Analysis port
		
		//Get config object
		if(!uvm_config_db #(bcd_agent_config)::get(this, "", "bcd_agent_config", m_config)) begin 
			`uvm_error("Config Error", "uvm_config_DB #(bcd_agent_config)::get cannot find resource bcd_agent_config")
		end
		m_bfm = m_config.mon_bfm; //Set virtual interface handle
		
	endfunction

	//Run Phase
	task run_phase(uvm_phase phase);

		item = bcd_txn::type_id::create("item");

		forever begin
			@(m_bfm.if_hundreds or m_bfm.if_tens or m_bfm.if_ones)
				//`uvm_info(get_type_name(), $sformatf("Hundreds: %b", m_bfm.if_hundreds), UVM_LOW);
				item.binary = m_bfm.if_binary;
				item.hundreds = m_bfm.if_hundreds;
				item.tens = m_bfm.if_tens;
				item.ones = m_bfm.if_ones;
				`uvm_info(get_type_name(), $sformatf("Monitor output: binary: %b hundreds: %b, tens: %b, ones: %b", item.binary, item.hundreds, item.tens, item.ones), UVM_LOW);
				bcd_mon_ap.write(item);
			
		end 
	endtask

endclass: bcd_monitor

// UVM Agent
//   Creates and contains monitor, driver and sequencer
class bcd_agent extends uvm_agent;
	//Register with UVM Factory
	`uvm_component_utils(bcd_agent)
	
	//Config Object
	bcd_agent_config m_cfg;
	
	//Component Members
	bcd_monitor m_monitor;
	bcd_driver m_driver;	
	uvm_analysis_port #(bcd_txn) ap;
	uvm_sequencer #(bcd_txn) m_sequencer;

	//Constructor
	function new(string name="bcd_agent", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	//Build Phase
	function void build_phase(uvm_phase phase);
		m_monitor = bcd_monitor::type_id::create("m_monitor", this); //Always present

		if (m_cfg == null)
			if(!uvm_config_db #(bcd_agent_config)::get(this, "", "bcd_agent_config", m_cfg) ) `uvm_fatal(get_type_name(), "bcd_agent_config not found in UVM_config_db")
		//Create driver and sequencer if agent is in active state (set in agent config object)
		if(m_cfg.active == UVM_ACTIVE) begin 
			m_driver = bcd_driver::type_id::create("m_driver", this);
			m_sequencer = uvm_sequencer #(bcd_txn)::type_id::create("m_sequencer", this);
		end
	endfunction: build_phase

	//Connect Phase
	function void connect_phase(uvm_phase phase);
		ap = m_monitor.bcd_mon_ap;
		m_monitor.m_bfm = m_cfg.mon_bfm; 

		if(m_cfg.active == UVM_ACTIVE) begin
			m_driver.seq_item_port.connect(m_sequencer.seq_item_export);
			m_driver.m_bfm = m_cfg.drv_bfm;
		end
	endfunction: connect_phase

endclass: bcd_agent

// UVM Scoreboard
//   Get sequence item through analysis imp, which is connected to the monitor's analysis port
//   Implements write() for analysis imp
//   Predicts bcd values based on a calculation
//   Compared predictions vs sequence items and counts correct and incorrect results
//   Sends results as UVM message during report phase
class scoreboard extends uvm_scoreboard;
	//Register with UVM Factory
	`uvm_component_utils(scoreboard)

	//Create uvm_analysis_imp(lementation) for monitor's ap write() function
	uvm_analysis_imp #(bcd_txn, scoreboard) sb_ap_imp;

	//Variables to track correct and incorrect transactions
	int correct = 0;
	int incorrect = 0;

	//Constructor
	function new(string name="scoreboard", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	//Predictor
        //Input: binary number stored in uvm sequence item of type bcd_txn.
        //Converts input to decimal, then calculates 4 bit value for 'hundreds', 'tens', and 'ones' of that number. 
        //Returns those results concatenated
	function bit[11:0] predict(bcd_txn item);
        bit [3:0] b_ones;
        bit [3:0] b_tens;
        bit [3:0] b_hundreds;

        int d_in = int'(item.binary);
        int d_ones = d_in % 10;
        int d_tens = $floor((d_in % 100) / 10);
        int d_hundreds = $floor((d_in % 1000) / 100);
        
        b_ones = 4'(d_ones);
        b_tens = 4'(d_tens);
        b_hundreds = 4'(d_hundreds);
		//`uvm_info(get_type_name(), $sformatf("Predict output: hundreds: %b, tens: %b, ones: %b", b_hundreds, b_tens, b_ones), UVM_LOW);
	    return {b_hundreds, b_tens, b_ones};
	endfunction: predict
    
    //Evaluator
      //Input: binary number stored in uvm sequence item of type bcd_txn.
      //Calls predict() and compares results
	function void eval(bcd_txn item);
		bit [11:0] prediction = predict(item);	
		if (prediction == {item.hundreds, item.tens, item.ones}) begin
            correct += 1;
		end
		else begin
			incorrect += 1;
			`uvm_info(get_type_name(),"Incorrect result detected by scoreboard.eval()", UVM_LOW);
			`uvm_info(get_type_name(), $sformatf("scoreboard.eval() prediction: hundreds: %b, tens: %b, ones: %b", prediction[11:8], prediction[7:4], prediction[3:0]), UVM_LOW);
			`uvm_info(get_type_name(), $sformatf("scoreboard input from monitor.analysis_port: hundreds: %b, tens: %b, ones: %b", item.hundreds, item.tens, item.ones), UVM_LOW);
		end
	endfunction: eval

	//Build Phase
	function void build_phase(uvm_phase phase);
		sb_ap_imp = new("sb_ap_imp", this); // Create the uvm_analysis_imp for the scoreboard (links to .write() of the analysis port of the monitor)
	endfunction: build_phase

	//Implementation of monitor.ap.write()	 
	function void write(bcd_txn item);
		`uvm_info(get_type_name(), $sformatf("Scoreboard input: binary: %b hundreds: %b, tens: %b, ones: %b", item.binary, item.hundreds, item.tens, item.ones), UVM_LOW);
        eval(item);
	endfunction

    //Report Phase
    function void report_phase(uvm_phase phase);
        `uvm_info(get_type_name(), $sformatf("Scoreboard results: incorrect: %d, correct: %d ", incorrect, correct), UVM_LOW); //Store incorrect values? Print to report file?
    endfunction

endclass: scoreboard

// UVM Environment
//   Creates and contains agent and scoreboard
class bcd_env extends uvm_env;
	//Register with UVM Factory
	`uvm_component_utils(bcd_env)

	//Sub component handles
	bcd_agent m_bcd_agent;
	scoreboard m_scoreboard;

	//Config object
	env_config m_cfg;

	//Constructor
	function new(string name="bcd_env", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	//Build Phase
	function void build_phase(uvm_phase phase);	
		if(!uvm_config_db #(env_config)::get(this, "", "env_config", m_cfg))`uvm_fatal("CONFIG_LOAD", "Cannot get() configuration env_config from uvm_config_db. Is it set()?")
		uvm_config_db #(bcd_agent_config)::set(this, "m_bcd_agent*", "bcd_agent_config", m_cfg.m_bcd_agent_cfg);

		m_bcd_agent = bcd_agent::type_id::create("m_bcd_agent", this); //Create agent
		if(m_cfg.has_scoreboard) begin
			m_scoreboard = scoreboard::type_id::create("m_scoreboard", this); //Create scoreboard
		end
	endfunction: build_phase

	function void connect_phase(uvm_phase phase);
		if(m_cfg.has_scoreboard) begin
			m_bcd_agent.ap.connect(m_scoreboard.sb_ap_imp);
		end
	endfunction: connect_phase

endclass: bcd_env

// UVM Test
//   Top of the testbench hierarchy 
//   Contains and creates configuration objects and environment

class my_test extends uvm_test;
	//Register with UVM Factory
	`uvm_component_utils(my_test)
	
	//Environment class
	bcd_env m_env;

	//Config Objects
	env_config m_env_cfg;
	bcd_agent_config m_bcd_cfg;

	//Constructor
	function new(string name="my_test", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	//Configure bcd agent
	function void configure_bcd_agent(bcd_agent_config cfg);
		cfg.active = UVM_ACTIVE;
		cfg.has_functional_coverage = 0;
		//cfg.has_scoreboard = 1;
	endfunction: configure_bcd_agent

	//Build Phase
	function void build_phase(uvm_phase phase);
		m_env_cfg = env_config::type_id::create("m_env_cfg"); //Create env config object
		m_bcd_cfg = bcd_agent_config::type_id::create("m_bcd_cfg"); //Create bcd agent config object
		configure_bcd_agent(m_bcd_cfg);
		
		// Get monitor and driver bfm handles
		if(!uvm_config_db #(virtual bcd_if)::get(this, "", "BCD_if", m_bcd_cfg.drv_bfm) ) `uvm_fatal(get_type_name(), "BCD_if not found in UVM_config_db")
		if(!uvm_config_db #(virtual bcd_if)::get(this, "", "BCD_if", m_bcd_cfg.mon_bfm) ) `uvm_fatal(get_type_name(), "BCD_if not found in UVM_config_db")

		m_env_cfg.m_bcd_agent_cfg = m_bcd_cfg; //set agent config member of env config
		uvm_config_db #(env_config)::set(this, "*", "env_config", m_env_cfg); //Add env_config to uvm_config_db

		//Create environment 
		m_env = bcd_env::type_id::create("m_env", this); 
	endfunction: build_phase

	//Run Phase
	task run_phase(uvm_phase phase);	
		base_sequence b_seq = base_sequence::type_id::create("b_seq");
		//`uvm_info("", "Test run phase started", UVM_LOW) 
		b_seq.start(m_env.m_bcd_agent.m_sequencer);
	endtask

endclass: my_test

//HW Description Language Top Layer. 
//  Instantiates pin interface and BFMs. 
//  Adds virtual BFM interfaces to uvm_config_db
 module hdl_top;  
	import uvm_pkg::*;
	
	//Instantiate pin interface to DUT
	bcd_if BCD_if();

	//Connect DUT to bcd_if0
	bcd dut0(
		.binary(BCD_if.if_binary),
		.hundreds(BCD_if.if_hundreds),
		.tens(BCD_if.if_tens),
		.ones(BCD_if.if_ones)
		//.output_ready(BCD_if.if_ready)
	);

	//Add virtual interfaces to uvm config db
	initial begin
		uvm_config_db #(virtual bcd_if)::set(null, "uvm_test_top", "BCD_if", BCD_if);
	end

endmodule: hdl_top

//HW Verification Language Top Layer
//Starts test
module hvl_top;
	import uvm_pkg::*;

	initial begin
		run_test("my_test");
	end
endmodule: hvl_top