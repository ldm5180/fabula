# Thin wrapper around Alire + gprbuild so the common flows are one word.
# Every target runs through `alr` (so the aunit/sml dependencies resolve).
# gnatprove and gnatformat may live only in ~/.alire/bin, so that directory
# is appended to PATH here as a fallback.

export PATH := $(PATH):$(HOME)/.alire/bin

.PHONY: all build test prove format validation shape example gate run ci help

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
gate: example
	python3 tools/byte_gate.py

## run         Build (debug) and run the example against the byte-gate feature
run: example
	./example/bin/debug/box_main tests/data/cwt/parser/1_first_scenario.feature

## ci          Run every gate, cheapest first
ci: shape format validation test prove example gate

## help        List targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'
