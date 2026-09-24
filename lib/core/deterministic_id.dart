import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'canonical_json.dart';

/// Deterministic content-derived id.
///
/// Pick ids are derived from the pick's identifying fields (subject, slate
/// date, market, statistic, direction and line) so that regenerating the same
/// picks yields the same ids and identical snapshots hash identically.
String contentId(String prefix, Map<String, Object?> fields) {
  final digest = sha256.convert(utf8.encode(canonicalJson(fields))).toString();
  return '$prefix-${digest.substring(0, 24)}';
}
