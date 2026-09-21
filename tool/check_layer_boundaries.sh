#!/usr/bin/env bash
#
# check_layer_boundaries.sh
#
# Two checks, both about which direction dependencies are allowed to point.
#
# CHECK 1 — every feature's domain/ stays pure Dart.
# For every feature under lib/features/ (sync, native_capture, flow), every
# `import` inside that feature's domain/ folder must be one of:
#   - dart:core or dart:async
#   - a relative import that resolves to another file still inside that
#     SAME feature's own domain/ folder (not a sibling feature's domain/,
#     and not that feature's own data/ or presentation/ folders either —
#     domain is the innermost layer, so nothing outside it is fair game)
#   - a relative import that resolves to exactly
#     lib/services/app_exception.dart — one narrow, named exception, not a
#     blanket "domain may import lib/services". AppException is a plain
#     Dart sealed class hierarchy (no package:http, no Flutter, nothing
#     domain/ isn't already allowed to contain on its own) that's
#     genuinely needed by more than one feature's domain-level status
#     types (see sync's SyncStatus.failed) — it lives in lib/services/
#     only because it's shared *infrastructure vocabulary*, not because
#     it's infrastructure *code*. Any other lib/services/ file
#     (api_client.dart, api_dtos.dart, api_http_client.dart — all of
#     which DO carry real or eventual infrastructure dependencies) is
#     still rejected exactly as before.
# Anything else fails: package:flutter/..., package:http/...,
# package:shared_preferences/..., package:path_provider/..., dart:io, any
# other dart:/package: import, or a relative import that resolves outside
# domain/ (other than the one named exception above).
#
# This is an ALLOWLIST, not a denylist. An earlier version of this script
# only failed a handful of named-bad prefixes (package:flutter/,
# package:http/, package:shared_preferences/) and was proven — not just
# suspected — to miss real ones: during the native_capture migration,
# dart:io and package:path_provider/ were never on that list, and a
# deliberately-misplaced data/ file under domain/ passed the check when it
# should have failed (see NOTES.md). A denylist only ever knows about the
# infrastructure whoever wrote it happened to think of; every new feature
# is free to introduce a new package the list has never heard of. An
# allowlist doesn't have that gap: nothing outside the two dart: prefixes
# and "still inside this feature's own domain/" is ever accepted, no
# matter what package it is or whether this script's author had ever heard
# of it.
#
# CHECK 2 — shared lib/services/ never imports from any feature.
# lib/services/ (currently just api_client.dart + api_dtos.dart) is meant
# to be depended ON by features, never the other way around — that's what
# "shared infrastructure" means. This check exists because that direction
# was violated for real, not hypothetically: ApiClient used to return
# flow's own ResolvedFlowManifest/FieldOption domain types straight from
# its method signatures, which meant lib/services/api_client.dart had to
# import from lib/features/flow/domain/ to even compile — shared code
# reaching into one specific feature's inner layer. Fixed by giving
# ApiClient its own DTOs (api_dtos.dart) and moving the DTO-to-domain
# mapping into flow's own data/ layer (FlowRepositoryImpl) — see NOTES.md.
# This check is what stops that particular mistake from quietly coming
# back: any `import '.../features/...'` line inside lib/services/ fails
# immediately, by file and line.
#
# Why any of this matters: domain/ is meant to be plain, framework-free
# Dart — just the app's own types and business rules, nothing about
# widgets, HTTP, on-device storage, or any other plugin — and shared
# infrastructure is meant to stay generic, not quietly coupled to one
# feature's types. Both are what let domain code be unit-tested with zero
# setup, and let real implementations be swapped for fakes in tests,
# without anything else in the app ever knowing the difference.
#
# This is a deliberately simple, grep/shell-based check — not a real Dart
# analyzer plugin. Good enough to catch an accidental bad import in CI
# without adding more tooling.
#
# Exit code: 0 if both checks are clean, 1 if any violation is found.

set -euo pipefail
cd "$(dirname "$0")/.."
repo_root=$(pwd -P)

violations=0

# ---- Check 1: lib/features/*/domain/ allowlist ----------------------------

domain_files=$(find lib/features -type d -name domain -exec find {} -name '*.dart' \; 2>/dev/null || true)

while IFS= read -r file; do
  [ -z "$file" ] && continue

  # The lib/features/<feature>/domain prefix this file belongs to —
  # relative imports must resolve to somewhere under this same path.
  feature_domain_dir=$(echo "$file" | sed -E 's#^(lib/features/[^/]+/domain)/.*#\1#')
  feature_domain_abs="$repo_root/$feature_domain_dir"
  file_dir=$(dirname "$file")

  import_lines=$(grep -nE "^import[[:space:]]+'[^']+'" "$file" || true)
  [ -z "$import_lines" ] && continue

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    lineno="${line%%:*}"
    rest="${line#*:}"
    target=$(echo "$rest" | sed -E "s/^import[[:space:]]+'([^']+)'.*/\1/")

    case "$target" in
      dart:core|dart:async)
        continue
        ;;
      dart:*|package:*)
        echo "FAIL: $file:$lineno imports '$target' - domain/ may only import dart:core, dart:async, or files within its own feature's domain/ folder."
        violations=1
        continue
        ;;
    esac

    # Anything else is a relative import — resolve it for real (cd there
    # and ask the filesystem, rather than trying to hand-parse ../ chains)
    # and confirm it lands inside this same feature's domain/ folder, or
    # is the one named exception (lib/services/app_exception.dart).
    resolved_dir=$(cd "$file_dir/$(dirname "$target")" 2>/dev/null && pwd -P || true)
    if [ -z "$resolved_dir" ]; then
      echo "FAIL: $file:$lineno imports '$target' - path could not be resolved."
      violations=1
      continue
    fi
    resolved_file="$resolved_dir/$(basename "$target")"

    case "$resolved_dir" in
      "$feature_domain_abs"|"$feature_domain_abs"/*)
        ;;
      *)
        if [ "$resolved_file" = "$repo_root/lib/services/app_exception.dart" ]; then
          continue
        fi
        echo "FAIL: $file:$lineno imports '$target', which resolves outside this feature's own domain/ folder."
        violations=1
        ;;
    esac
  done <<< "$import_lines"
done <<< "$domain_files"

# ---- Check 2: lib/services/ must never import a feature -------------------

service_files=$(find lib/services -name '*.dart' 2>/dev/null || true)

while IFS= read -r file; do
  [ -z "$file" ] && continue

  bad=$(grep -nE "^import[[:space:]]+'[^']*/features/" "$file" || true)
  if [ -n "$bad" ]; then
    echo "FAIL: $file imports from a feature - shared lib/services/ must never depend on any single feature:"
    echo "$bad"
    violations=1
  fi
done <<< "$service_files"

if [ "$violations" -ne 0 ]; then
  echo ""
  echo "check_layer_boundaries: FAILED - see violations above."
  exit 1
fi

echo "check_layer_boundaries: OK - domain/ stays pure per feature, and lib/services/ stays feature-agnostic."
exit 0
