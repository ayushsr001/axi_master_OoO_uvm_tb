class axi_agent #(parameter int DATA_WIDTH = 64) extends uvm_agent;

  `uvm_component_param_utils(axi_agent #(DATA_WIDTH))

  uvm_sequencer #(axi_transaction)  sqr;
  axi_m_driver  #(DATA_WIDTH)       drv;
  axi_monitor   #(DATA_WIDTH)       mon;

  uvm_analysis_port #(axi_transaction) ap;   // re-exported so the env connects to the agent, not the monitor

  virtual axi_if vif;

  function new(string name = "axi_agent", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db #(virtual axi_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "No virtual interface present")

    // hand the same vif to the children
    uvm_config_db #(virtual axi_if)::set(this, "mon", "vif", vif);
    mon = axi_monitor #(DATA_WIDTH)::type_id::create("mon", this);
    ap  = new("ap", this);

    // is_active comes from uvm_agent; default is UVM_ACTIVE. Override from the test via config_db.
    if (get_is_active() == UVM_ACTIVE) begin
      uvm_config_db #(virtual axi_if)::set(this, "drv", "vif", vif);
      sqr = uvm_sequencer #(axi_transaction)::type_id::create("sqr", this);
      drv = axi_m_driver #(DATA_WIDTH)::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mon.ap.connect(ap);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass : axi_agent
