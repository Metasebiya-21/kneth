# There was no CI/Makefile setup in this project before this migration —
# this is a minimal one so the new boundary check (and the existing
# analyze/test commands) run from one place instead of being remembered by
# hand. Wire a real CI provider (GitHub Actions, etc.) to run `make ci`
# once one exists.

.PHONY: analyze test check-boundaries ci

analyze:
	flutter analyze

test:
	flutter test

check-boundaries:
	./tool/check_layer_boundaries.sh

# Everything that should block a merge.
ci: analyze check-boundaries test
