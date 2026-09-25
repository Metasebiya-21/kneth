# There was no CI/Makefile setup in this project before this migration —
# this is a minimal one so the new boundary check (and the existing
# analyze/test commands) run from one place instead of being remembered by
# hand. Wire a real CI provider (GitHub Actions, etc.) to run `make ci`
# once one exists.

.PHONY: analyze test check-boundaries ci live record-stac-fixtures

analyze:
	flutter analyze

test:
	flutter test

check-boundaries:
	./tool/check_layer_boundaries.sh

# Everything that should block a merge.
ci: analyze check-boundaries test

# Live tier: drives kneth's own Dart code against a RUNNING onboarding-platform
# (:8000) + Keycloak (:8080) with the seeded data. Creates real cases/records.
# Each test skips itself if the backend isn't reachable. Not part of `ci`, but
# note a plain `flutter test` also picks these files up and will run them if a
# backend happens to be up.
live:
	flutter test test/live

# Re-records the real backend responses the offline parity tests replay.
record-stac-fixtures:
	./tool/record_stac_fixtures.sh
