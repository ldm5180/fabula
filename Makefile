# Thin wrapper around Alire + gprbuild so the common flows are one word.
# Every target runs through `alr` (so the aunit/sml dependencies resolve).
# gnatprove and gnatformat may live only in ~/.alire/bin, so that directory
# is appended to PATH here as a fallback.

export PATH := $(PATH):$(HOME)/.alire/bin

.PHONY: all build test prove format validation shape example gate recapture-check run demo ci help

all: build

## build       Build the library (Alire profile decides the switches)
build:
	alr build

## test        Build and run the AUnit suite in both modes (per-test output)
test:
	alr --non-interactive test

## prove       Run the SPARK proof and the proof-closure lint
prove:
	alr exec -- gnatprove -P proof/proof.gpr -j0 --level=2 --checks-as-errors=on --warnings=error
	python3 tools/proof_closure_lint.py

## format      Check formatting (gnatformat --check, no warnings)
format:
	alr exec -- gnatformat --no-project --check $$(git ls-files '*.ads' '*.adb')

## validation  Build with the validation profile (warnings-as-errors)
validation:
	alr --non-interactive build --validation

## shape       Run the lint selftests, then the subprogram-shape lint
shape:
	python3 tools/shape_check.py --selftest
	python3 tools/proof_closure_lint.py --selftest
	python3 tools/shape_check.py

## example     Build the box example binary, both modes
example: build
	alr exec -- gprbuild -p -P example/example.gpr -XMODE=debug
	alr exec -- gprbuild -p -P example/example.gpr -XMODE=release

## gate        Byte-gate the RELEASE example against the pinned oracle
#              (the corpus manifest, then the example/features/ one --
#              both run in well under a second, so both stay in `ci`)
gate: example
	python3 tools/byte_gate.py
	python3 tools/byte_gate.py tests/data/golden/example_manifest.txt

## recapture-check  Re-run the reference interpreter over every golden and
#              compare byte for byte. Local only, not part of `ci`: it
#              needs both oracle builds, named by FABULA_ORACLE and
#              FABULA_ORACLE_PATCHED (tools/recapture_goldens.py says how
#              to build them).
recapture-check:
	python3 tools/recapture_goldens.py --selftest
	python3 tools/recapture_goldens.py --check

## run         Build (debug) and run the example against the byte-gate feature
run: example
	./example/bin/debug/box_main tests/data/cwt/parser/1_first_scenario.feature

## demo        Run the RELEASE example over example/features/; exit 1 by
#              design (11_manual_fails.feature fails one scenario on
#              purpose). A fresh run of the pinned oracle over the same
#              directory reports:
#                39 Scenarios (3 failed, 2 skipped, 34 passed)
#                119 Steps (1 undefined, 12 skipped, 106 passed)
#              This target checks both: fabula's own exit code and its
#              summary lines must match those counts exactly.
demo: example
	@output="$$(./example/bin/release/box_main example/features 2>&1)"; \
	status=$$?; \
	printf '%s\n' "$$output"; \
	if [ "$$status" -ne 1 ]; then \
		echo "demo: expected exit 1, got $$status" >&2; \
		exit 1; \
	fi; \
	if ! printf '%s\n' "$$output" | grep -qxF '39 Scenarios (3 failed, 2 skipped, 34 passed)'; then \
		echo "demo: scenario summary drifted from the pinned oracle" >&2; \
		exit 1; \
	fi; \
	if ! printf '%s\n' "$$output" | grep -qxF '119 Steps (1 undefined, 12 skipped, 106 passed)'; then \
		echo "demo: step summary drifted from the pinned oracle" >&2; \
		exit 1; \
	fi; \
	echo "demo: exit 1 as expected; summary matches the pinned oracle"

## ci          Run every gate, cheapest first
ci: shape format validation test prove example gate demo

## help        List targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'
