class UnitSanitizer {
  static String? clean(String? unit) {
    final raw = unit?.trim();
    if (raw == null || raw.isEmpty) return null;

    final seen = <String>{};
    final deduped = raw
        .split(RegExp(r'\s+'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && seen.add(p))
        .toList(growable: false);

    if (deduped.isEmpty) return null;

    // Keep percent symbol once and at the end when mixed with named units.
    final withoutPercent = deduped.where((p) => p != '%').toList(growable: false);
    final hasPercent = deduped.contains('%');
    if (hasPercent && withoutPercent.isNotEmpty) {
      return '${withoutPercent.join(' ')} %';
    }
    return deduped.join(' ');
  }
}

String getDisplayUnit(Map test) {
  return UnitSanitizer.clean(test['unit']?.toString()) ?? '';
}

String formatDisplayValueWithUnit(
  Map test, {
  String valueKey = 'value',
}) {
  final value = (test[valueKey] ?? '').toString().trim();
  final unit = getDisplayUnit(test);
  if (value.isEmpty) return '-';
  if (unit.isEmpty) return value;
  return '$value $unit';
}
