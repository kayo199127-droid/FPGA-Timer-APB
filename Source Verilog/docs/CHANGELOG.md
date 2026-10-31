# Final Project Change Log

## Corrected package – 31 October 2026

- Corrected team ownership to match the assignment screenshot: Member 1 Timer Divider; Member 2 APB Slave Interface; Member 3 System Integration and Verification; Member 4 Timer Core; Member 5 Register Bank.
- Kept the timer divider, timer core, APB slave, register bank, integration wrapper and top-level as separate RTL files.
- Added dedicated self-checking unit testbenches for the APB slave and timer core; retained register/divider unit benches and the system-level top test.
- Updated ModelSim/Questa and Icarus runner scripts to compile and execute the five canonical testbenches.
- Ensured testbench failures terminate with `$fatal` rather than reporting a false successful exit.
- Updated the register test for the Design SPEC W1C priority and corrected the integrated test's TCR reset expectation to match the supplied register RTL/testbench.
- Recorded source conflicts and chosen interpretations in `docs/DESIGN_DECISIONS.md` and `docs/INTERFACE_AGREEMENT.md`, including divider interval, TCR reset, W1C priority, counter clear/preload, PSLVERR policy, APB port naming/address width and compare-event gating.
- Added one group report and five role-specific individual report drafts.

## Verification status

Static structural audit and Python Golden Model self-test pass. HDL compile/simulation, Gowin synthesis/timing and physical-board validation have not been executed in the authoring environment. Instructor confirmation is still required for the documented source/specification conflicts.
