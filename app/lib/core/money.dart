/// FCFA amounts are whole numbers: `150 000 FCFA` (non-breaking spaces so a figure is never split across lines).
String formatFcfa(int value, {bool unit = true}) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  return '${negative ? '-' : ''}$buf${unit ? ' FCFA' : ''}';
}

/// Digits typed by a person ("150 000", "150000 FCFA") → 150000, or null when empty.
int? parseFcfa(String text) {
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? null : int.tryParse(digits);
}

String formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
