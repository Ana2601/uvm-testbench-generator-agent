PY ?= python3
UVM_COMMIT ?= 78c0654          # accellera-official/uvm-core, release 2020-3.1
export UVM_HOME ?= $(CURDIR)/third_party/uvm-core/src

.PHONY: test demo demo-uvm uvm-lib check live clean

## unit tests: plan validation, model-bug and DUT-bug detection, mutation analysis (~10 s)
test:
	$(PY) -m unittest -v tests/test_uvmgen.py

## replay all trajectories: Icarus testbenches + coverage + mutation analysis (~1 min)
demo:
	$(PY) -m uvmgen

## the same, plus build and run every generated UVM testbench on Verilator (~5 min)
demo-uvm: uvm-lib
	$(PY) -m uvmgen --uvm

## Accellera UVM library (Apache-2.0), pinned
uvm-lib: third_party/uvm-core/src/uvm_pkg.sv
third_party/uvm-core/src/uvm_pkg.sv:
	git clone -q https://github.com/accellera-official/uvm-core.git third_party/uvm-core
	git -C third_party/uvm-core checkout -q $(strip $(UVM_COMMIT))

check:
	$(PY) scripts/check_results.py

## live agent with Claude (needs ANTHROPIC_API_KEY or an `ant auth login` profile)
live:
	$(PY) -m uvmgen --backend claude --out results_live $(if $(DESIGN),--design $(DESIGN)) $(if $(UVM),--uvm)

clean:
	rm -rf results/*/work results/*/uvm_build results_live tests/__pycache__ uvmgen/__pycache__
