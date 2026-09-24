import 'dart:convert';

/// Deterministic JSON encoding used for snapshot hashing.
///
/// Keys are sorted recursively so that the same logical payload always
/// produces byte-identical output and therefore a stable SHA-256.
String canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _canonicalize(value[k])};
  }
  if (value is List) {
    return value.map(_canonicalize).toList();
  }
  return value;
}
