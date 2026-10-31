#!/usr/bin/env python3
"""Structural RTL/interface audit for the FAP201 IP Timer project.

This is a lightweight source check, not an HDL compiler or simulator.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "rtl"
TB = ROOT / "tb"

REQUIRED = {
    "apb_slave.v": "apb_slave",
    "register.v": "register",
    "timer_divider.v": "timer_divider",
    "timer_core.v": "timer_core",
    "counter.sv": "counter",
    "timer_top.v": "timer_top",
}
CANONICAL_TBS = {"tb_apb_slave.v", "tb_register.v", "tb_timer_divider.v", "tb_timer_core.v", "tb_timer_top.v"}
errors = []
modules = {}

def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//.*", "", text)
    return text

def balanced_block(text: str, open_pos: int):
    depth = 0
    for i in range(open_pos, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return text[open_pos + 1:i]
    return None

def module_ports(text: str, name: str):
    m = re.search(r"\bmodule\s+" + re.escape(name) + r"\b", text)
    if not m:
        return None
    pos = m.end()
    while pos < len(text) and text[pos].isspace():
        pos += 1
    if pos < len(text) and text[pos] == "#":
        pos += 1
        while pos < len(text) and text[pos].isspace():
            pos += 1
        if pos >= len(text) or text[pos] != "(":
            return None
        block = balanced_block(text, pos)
        if block is None:
            return None
        pos += len(block) + 2
    while pos < len(text) and text[pos].isspace():
        pos += 1
    if pos >= len(text) or text[pos] != "(":
        return None
    block = balanced_block(text, pos)
    if block is None:
        return None
    return set(re.findall(r"\b(?:input|output|inout)\s+(?:(?:wire|reg|logic)\s+)?(?:\[[^\]]+\]\s*)?(\w+)", block))

def instantiations(text: str, known_modules):
    clean = strip_comments(text)
    found = []
    for mod in known_modules:
        for m in re.finditer(r"\b" + re.escape(mod) + r"\b", clean):
            prefix = clean[max(0, m.start()-12):m.start()]
            if re.search(r"\bmodule\s+$", prefix):
                continue
            pos = m.end()
            while pos < len(clean) and clean[pos].isspace():
                pos += 1
            if pos < len(clean) and clean[pos] == "#":
                pos += 1
                while pos < len(clean) and clean[pos].isspace():
                    pos += 1
                if pos >= len(clean) or clean[pos] != "(":
                    continue
                param_block = balanced_block(clean, pos)
                if param_block is None:
                    errors.append(f"Could not parse parameters for {mod} at {source.name if 'source' in globals() else 'source'}")
                    continue
                pos += len(param_block) + 2
            while pos < len(clean) and clean[pos].isspace():
                pos += 1
            inst = re.match(r"\w+", clean[pos:])
            if not inst:
                continue
            inst_name = inst.group(0)
            pos += len(inst_name)
            while pos < len(clean) and clean[pos].isspace():
                pos += 1
            if pos >= len(clean) or clean[pos] != "(":
                continue
            block = balanced_block(clean, pos)
            if block is None:
                errors.append(f"Could not parse instance port list for {mod}.{inst_name}")
                continue
            mapped = set(re.findall(r"\.\s*(\w+)\s*\(", block))
            found.append((mod, inst_name, mapped))
    return found

for filename, modname in REQUIRED.items():
    p = RTL / filename
    if not p.exists():
        errors.append(f"Missing RTL: {filename}")
        continue
    text = strip_comments(p.read_text(encoding="utf-8"))
    mods = re.findall(r"(?m)^\s*module\s+(\w+)", text)
    ends = len(re.findall(r"(?m)^\s*endmodule\b", text))
    if mods != [modname]:
        errors.append(f"{filename}: expected only module {modname}, found {mods}")
    if len(mods) != ends:
        errors.append(f"{filename}: module/endmodule count mismatch {len(mods)}/{ends}")
    if len(re.findall(r"\bbegin\b", text)) != len(re.findall(r"\bend\b", text)):
        errors.append(f"{filename}: begin/end count mismatch")
    if len(re.findall(r"\bcase\b", text)) != len(re.findall(r"\bendcase\b", text)):
        errors.append(f"{filename}: case/endcase count mismatch")
    modules[modname] = module_ports(text, modname)
    if modules[modname] is None:
        errors.append(f"{filename}: unable to parse ANSI port list for {modname}")

for p in sorted(TB.glob("*")):
    if p.is_file() and p.suffix.lower() in {".v", ".sv"} and p.name not in CANONICAL_TBS:
        errors.append(f"Non-canonical testbench remains in tb/: {p.name}; archive or integrate it explicitly")
for name in sorted(CANONICAL_TBS):
    if not (TB / name).exists():
        errors.append(f"Missing canonical testbench: {name}")

# Validate module port names at every RTL module-instantiation boundary.
for source in list(RTL.glob("*")) + list(TB.glob("*")):
    if not source.is_file() or source.suffix.lower() not in {".v", ".sv"}:
        continue
    text = source.read_text(encoding="utf-8")
    for mod, inst, mapped in instantiations(text, modules):
        expected = modules.get(mod)
        if expected is None:
            continue
        extra = mapped - expected
        missing = expected - mapped
        if extra:
            errors.append(f"{source.name}: {mod} instance {inst} maps unknown ports: {sorted(extra)}")
        # All current RTL instances use named port maps; missing ports are a wiring error.
        if missing:
            errors.append(f"{source.name}: {mod} instance {inst} leaves ports unconnected: {sorted(missing)}")

if errors:
    for e in errors:
        print("[FAIL]", e)
    sys.exit(1)

print("[PASS] Structural audit: RTL modules, balanced blocks, canonical testbenches and named port maps are consistent.")
print("[INFO] This check does not elaborate or simulate HDL. Run ModelSim/Questa or Icarus before functional sign-off.")
