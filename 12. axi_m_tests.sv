class axi_base_test extends uvm_test;
  `uvm_component_utils(axi_base_test)

  axi_env env;

  function new(string name = "axi_base_test", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = axi_env::type_id::create("env", this);
  endfunction

  // derived tests override this to choose the sequence
  virtual task run_seq(uvm_phase phase);
    axi_wr_rd_seq seq = axi_wr_rd_seq::type_id::create("seq");
    seq.set_starting_phase(phase);              // lets the sequence raise and drop the objection
    seq.start(env.agent.sqr);                   // this call binds the sequence to the sequencer
  endtask

  task run_phase(uvm_phase phase);
    run_seq(phase);
    #200ns;                                     // short drain so the last response reaches the monitor
  endtask
endclass

class axi_burst_test extends axi_base_test;
  `uvm_component_utils(axi_burst_test)
  function new(string name = "axi_burst_test", uvm_component parent); super.new(name, parent); endfunction
  virtual task run_seq(uvm_phase phase);
    axi_burst_seq seq = axi_burst_seq::type_id::create("seq");
    seq.set_starting_phase(phase);
    seq.start(env.agent.sqr);
  endtask
endclass

class axi_rand_test extends axi_base_test;
  `uvm_component_utils(axi_rand_test)
  function new(string name = "axi_rand_test", uvm_component parent); super.new(name, parent); endfunction
  virtual task run_seq(uvm_phase phase);
    axi_rand_seq seq = axi_rand_seq::type_id::create("seq");
    seq.num_iter = 50;
    seq.set_starting_phase(phase);
    seq.start(env.agent.sqr);
  endtask
endclass
