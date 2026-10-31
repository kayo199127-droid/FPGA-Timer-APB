.PHONY: sim clean audit
sim:
	./sim/run_iverilog.sh

audit:
	python3 tools/static_audit.py
	python3 tools/golden_model.py

clean:
	rm -f results/*.out results/*.log results/*.vcd results/waveforms/*.vcd
