# Upstream corpus

The feature files in `parser/` are the reference interpreter's own
inputs. They are cwt-cucumber's `fuzz/corpus/parser/` at commit
662b4e4, kept byte-identical. Only `parser/MANIFEST.md` is fabula's.

Some of these files use C++ wording, for example `cuke::` calls and
`std::vector`. That wording is upstream text. It stays because the
files must match the oracle's inputs byte for byte. The Ada-worded
versions that teach fabula are in `example/features/`.

Do not edit a file here. `parser/MANIFEST.md` says how the unit tests
use the corpus. cwt-cucumber's MIT license is in `LICENSE`.
