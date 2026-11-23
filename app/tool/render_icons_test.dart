// Renders the launcher icon (1024 px) from the same painter the app uses.
//   flutter test tool/render_icons_test.dart   then   bash tool/apply_icons.sh
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:scolaris/core/logo.dart';

void main() {
  for (final (name, radius) in const [('icon-1024.png', 112.0), ('icon-ios-1024.png', 0.0)]) {
    test('render $name', () async {
      const size = 1024.0;
      final rec = ui.PictureRecorder();
      ScolarisMarkPainter(cornerRadius: radius).paint(ui.Canvas(rec), const ui.Size(size, size));
      final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
      final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      final out = File('build/$name')..createSync(recursive: true);
      out.writeAsBytesSync(bytes);
      expect(out.lengthSync(), greaterThan(5000));
    });
  }
}
