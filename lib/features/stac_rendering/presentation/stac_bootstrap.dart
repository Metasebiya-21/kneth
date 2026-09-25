import 'dart:async';

import 'package:stac/stac.dart';

import 'parsers/kneth_conditional_parser.dart';
import 'parsers/kneth_date_parser.dart';
import 'parsers/kneth_dropdown_parser.dart';
import 'parsers/kneth_fallback_parsers.dart';
import 'parsers/kneth_liveness_capture_parser.dart';
import 'parsers/kneth_photo_capture_parser.dart';
import 'parsers/kneth_signature_capture_parser.dart';
import 'parsers/kneth_text_parser.dart';

/// Every custom Stac parser the backend's `kneth_*` widget types need
/// (STAC_MIGRATION_SCOPING.md section 11.3).
const List<StacParser> kKnethStacParsers = [
  KnethConditionalParser(),
  KnethTextParser(),
  KnethDateParser(),
  KnethDropdownParser(),
  KnethPhotoCaptureParser(),
  KnethSignatureCaptureParser(),
  KnethLivenessCaptureParser(),
  KnethUnsupportedFieldParser(),
  KnethNativeCaptureParser(),
];

bool _initialized = false;

/// Registers the parsers with Stac, once. Stac keeps its parser list and
/// registry as process-wide statics (section 8's risks), so a second call
/// would append duplicates; hence the guard. `Stac.initialize`'s body has no
/// `await`, so registration has happened by the time this returns.
///
/// No `StacOptions` (no Stac Cloud project) is passed, and kneth never uses
/// `Stac(routeName:)` or `StacApp` cloud themes — the only two paths to
/// `api.stac.dev` (section 2.2). Stac's own Dio is created by `initialize`
/// but nothing here ever makes a request with it: manifests are fetched
/// through `ApiClient`.
void ensureKnethStacInitialized() {
  if (_initialized) return;
  _initialized = true;
  unawaited(Stac.initialize(parsers: kKnethStacParsers));
}
