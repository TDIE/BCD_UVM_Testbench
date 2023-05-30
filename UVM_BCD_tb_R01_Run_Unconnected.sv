// UVM TB for bcd+if.sv (part of Logic Solver demo project for Cyclone V FPGA)

`include "uvm_macros.svh"

import uvm_pkg::*;



class bcd_agent_config extends uvm_object;
	`uvm_object_utils(bcd_agent_config)

	//BFM Virtual Interfaces
	virtual bcd_monitor_bfm mon_bfm;
	virtual bcd_driver_bfm drv_bfm;

	//Data Members
	uvm_active_passive_enum active = UVM_ACTIVE;
	bit has_functional_coverage = 0;
	//bit has_scoreboard = 1;

	//Constructor
	function new(string name = "bcd_agent_config");
		super.new(name);
	endfunction

endclass: bcd_agent_config 

class env_config extends uvm_object;
	`uvm_object_utils(env_config);

	//Environment configuration options	
	bit has_functional_coverage = 0;
	bit has_scoreboard = 1;

	//Configurations for the sub_component(s)
	bcd_agent_config m_bcd_agent_cfg;

	virtual bcd_monitor_bfm bcd_mon_bfm;
	virtual bcd_driver_bfm bcd_driv_bfm;

	function new(string name="env_config");
		super.new(name);
	endfunction

endclass

class bcd_txn extends uvm_sequence_item;
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
	//constraint ls_nibble_only {bin <= 9'b0_0000_1111;}


endclass: bcd_txn

class base_sequence extends uvm_sequence #(bcd_txn);
	`uvm_object_utils(base_sequence)

	bcd_txn seq_item;
	int n_times = 1;

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
		
		//Send a randomized sequence item "n_times"
		repeat (n_times) begin
			start_item(seq_item);
			assert(seq_item.randomize());
			finish_item(seq_item);
		end

		//Drop objection
		if (starting_phase != null) begin
			starting_phase.drop_objection(this);
		end
	endtask

endclass: base_sequence

interface bcd_monitor_bfm(input logic [9:0] binary
			 , input logic [3:0] hundreds
			 , input logic [3:0] tens
		 	 , input logic [3:0] ones
);

	//Data Members
	bcd_monitor proxy;

	//Methods
	/*task monitor(bcd_txn item);

		@(binary)
			item.hundreds = hundreds;
			item.tens = tens;
			item.ones = ones;
			//proxy.notify_transaction(txn);  //Difference with proxy.write(txn)?

	endtask*/

endinterface: bcd_monitor_bfm

interface bcd_driver_bfm(input logic [9:0] binary); 

	//Data Members
	bcd_driver proxy;

	//Methods
	task run(bcd_txn item);
		binary = item.binary
	endtask
endinterface: bcd_driver_bfm

class bcd_driver extends uvm_driver #(bcd_txn);
	//Register with UVM Factory
	`uvm_component_utils(bcd_driver)

	//Constructor
	function new(string name="bcd_driver", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	//Virtual interface handle
	virtual bcd_driver_bfm m_bfm;
	// (!if... get the m_bfm drv handle from uvm_config_db)
	//m_bfm.proxy = this //Set proxy?

	//Build Phase
	function void build_phase(uvm_phase phase);

	endfunction: build_phase

	//Connect Phase
	function void connect_phase(uvm_phase phase);
		
	endfunction: connect_phase

	//Run Phase
	task run_phase(uvm_phase phase);
		bcd_txn item;

		forever begin
			seq_item_port.get_next_item(item);
			//m_bfm.binary = item.binary; 
			//m_bfm.run(item); //Let BFM handle "pin toggles" to support emulation. TODO: look into error: illegal reference to net binary
			seq_item_port.item_done(); 

		end
	endtask: run_phase

	//Config
	//Sequencer	

	

endclass: bcd_driver

class bcd_monitor extends uvm_monitor;
	//Register with UVM Factory
	`uvm_component_utils(bcd_monitor)

	uvm_analysis_port #(bcd_txn) bcd_mon_ap; //Analysis port
	virtual bcd_monitor_bfm m_bfm; //BFM handle
	bcd_agent_config m_config; //Config, contains monitor bfm handle
	bcd_txn item; //Sequence item


	//Constructor
	function new(string name="bcd_monitor", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	//Build Phase 
	function void build_phase(uvm_phase phase);
		//bcd_mon_ap = new("bcd_mon_ap", this); //Analysis port
		//Get config object
		if(!uvm_config_db #(bcd_agent_config)::get(this, "", "bcd_agent_config", m_config)) begin 
			`uvm_error("Config Error", "uvm_config_DB #(bcd_agent_config)::get cannot find resource bcd_agent_config")
		end
		m_bfm = m_config.mon_bfm; //Set local virtual interface property
		//m_bfm.proxy =this; //Set BFM proxy handle?
	endfunction

	//Run Phase
	task run_phase(uvm_phase phase);
		forever begin
			@(m_bfm.binary)
			item.hundreds = m_bfm.hundreds;
			item.tens = m_bfm.tens;
			item.ones = m_bfm.ones;
		end
		//m_bfm.monitor(item);
	endtask

	//function void notify_transaction(bcd_txn item); //Used by BFM to return transactions
		//bcd_mon_ap.write(item);
	//endfunction


endclass: bcd_monitor

class bcd_agent extends uvm_agent;
	//Register with UVM Factory
	`uvm_component_utils(bcd_agent)
	
	//Data Members
	bcd_agent_config m_cfg;
	
	//Component Members
	bcd_monitor m_monitor;
	bcd_driver m_driver;	
	uvm_analysis_port #(bcd_txn) ap;
	uvm_sequencer #(bcd_txn) m_sequencer;
	//Add coverage monitor// bcd_coverage_monitor m_fcov_monitor

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
		/*if(m_cfg.has_functional_coverage) begin
			m_fcov_monitor = bcd_coverage_monitor::typde_id::create("m_fcov_monitor", this);
		end*/
	endfunction: build_phase

	function void connect_phase(uvm_phase phase);
		ap = m_monitor.bcd_mon_ap;
		m_monitor.m_bfm = m_cfg.mon_bfm;

		if(m_cfg.active == UVM_ACTIVE) begin
			m_driver.seq_item_port.connect(m_sequencer.seq_item_export);
			m_driver.m_bfm = m_cfg.drv_bfm;
		end
	endfunction: connect_phase


endclass: bcd_agent

class scoreboard extends uvm_scoreboard;
	//Register with UVM Factory
	`uvm_component_utils(scoreboard)

	//Constructor
	function new(string name="scoreboard", uvm_component parent=null);
		super.new(name, parent);
	endfunction

 
endclass: scoreboard

class bcd_env extends uvm_env;
	//Register with UVM Factory
	`uvm_component_utils(bcd_env)

	//Sub component handles
	bcd_agent m_bcd_agent;
	scoreboard m_scoreboard;

	//Config objects
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
			//m_bcd_agent.ap.connect(m_scoreboard.bcd.analysis_export); //TODO:add to scoreboard class analysis bcd.analysis_export()
		end

	endfunction: connect_phase

	//Run Phase
	

endclass: bcd_env

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
		//cfg.has_scoreboard = 0;
	endfunction: configure_bcd_agent

	//Build Phase
	function void build_phase(uvm_phase phase);
		m_env_cfg = env_config::type_id::create("m_env_cfg"); //Create env config object
		//TODO: configure m_env_cfg
		m_bcd_cfg = bcd_agent_config::type_id::create("m_bcd_cfg"); //Create bcd agent config object
		configure_bcd_agent(m_bcd_cfg);
		
		// Get monitor and driver bfm handles
		if(!uvm_config_db #(virtual bcd_driver_bfm)::get(this, "", "BCD_drv_bfm", m_bcd_cfg.drv_bfm) ) `uvm_fatal(get_type_name(), "BCD_drv_bfm not found in UVM_config_db")
		if(!uvm_config_db #(virtual bcd_monitor_bfm)::get(this, "", "BCD_mon_bfm", m_bcd_cfg.mon_bfm) ) `uvm_fatal(get_type_name(), "BCD_mon_bfm not found in UVM_config_db")		
		
		m_env_cfg.m_bcd_agent_cfg = m_bcd_cfg; //set agent config member of env config
		uvm_config_db #(env_config)::set(this, "*", "env_config", m_env_cfg); //Add env_config to uvm_config_db

		//Create environment 
		m_env = bcd_env::type_id::create("m_env", this); 
	endfunction: build_phase

//	//Run Phase
	task run_phase(uvm_phase phase);
		base_sequence b_seq = base_sequence::type_id::create("b_seq");
		//execute body method of b_seq?
	endtask
endclass: my_test

 module hdl_top;  

	//Instantiate pin interface to DUT
	bcd_if bcd_if0;
        
	//Instantiate BFM interfaces
	bcd_monitor_bfm BCD_mon_bfm(
		.binary (bcd_if0.mp_mon.if_binary),
		.hundreds(bcd_if0.mp_mon.if_hundreds),
		.tens(bcd_if0.mp_mon.if_tens),
		.ones(bcd_if0.mp_mon.if_ones)
	);

	bcd_driver_bfm BCD_drv_bfm(
		.binary (bcd_if0.mp_drv.if_binary)
	);

	//Connect DUT to bcd_if0
	bcd dut0(
		.binary(bcd_if0.if_binary),
		.hundreds(bcd_if0.if_hundreds),
		.tens(bcd_if0.if_tens),
		.ones(bcd_if0.if_ones)
	);

	//Add virtual interfaces to uvm config db
	initial begin
		uvm_config_db #(virtual bcd_monitor_bfm)::set(null, "uvm_test_top", "BCD_mon_bfm", BCD_mon_bfm);
		uvm_config_db #(virtual bcd_driver_bfm)::set(null, "uvm_test_top", "BCD_drv_bfm", BCD_drv_bfm);
	end

	

endmodule: hdl_top

module hvl_top;
	import uvm_pkg::*;

	initial begin
		run_test("my_test");
	end
endmodule: hvl_top