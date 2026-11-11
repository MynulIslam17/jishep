// Regenerates legal_site/ (the public Terms of Use and Privacy Policy pages)
// from lib/features/legal/legal_content.dart.
//
//   dart run tool/build_legal_pages.dart
//   firebase deploy --only hosting --project gps-cielo

import 'dart:io';

import 'package:gps_cielo/features/legal/legal_html.dart';

void main() {
  final dir = Directory('legal_site')..createSync();
  LegalHtml.site().forEach((name, html) {
    File('${dir.path}/$name').writeAsStringSync(html);
    stdout.writeln('wrote legal_site/$name');
  });
}
