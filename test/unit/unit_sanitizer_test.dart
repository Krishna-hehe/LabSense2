import 'package:flutter_test/flutter_test.dart';
import 'package:clear_health/core/utils/unit_sanitizer.dart';

void main() {
  test('UnitSanitizer.clean removes duplicate unit tokens', () {
    expect(UnitSanitizer.clean('% fL %'), 'fL %');
    expect(UnitSanitizer.clean('10^3/µL /c.mm 10^3/µL'), '10^3/µL /c.mm');
  });

  test('formatDisplayValueWithUnit pairs value and sanitized unit', () {
    final row = {'value': '88.6', 'unit': '% fL %'};
    expect(formatDisplayValueWithUnit(row), '88.6 fL %');
  });
}
