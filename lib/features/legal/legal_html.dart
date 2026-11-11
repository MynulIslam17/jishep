// Pure Dart: renders the legal documents as standalone web pages for
// Firebase Hosting (see tool/build_legal_pages.dart and legal_site/).

import 'package:gps_cielo/features/legal/legal_content.dart';
import 'package:gps_cielo/features/legal/legal_info.dart';

abstract final class LegalHtml {
  /// File name → page contents for everything in `legal_site/`.
  static Map<String, String> site() => {
    'index.html': _index(),
    for (final doc in LegalContent.all) '${doc.slug}.html': page(doc),
  };

  static String page(LegalDocument doc) {
    final body = StringBuffer()
      ..writeln('<h1>${_e(doc.title)}</h1>')
      ..writeln('<p class="meta">${_e(doc.lastUpdated)}</p>')
      ..writeln('<p>${_linkify(doc.intro)}</p>');
    for (final section in doc.sections) {
      body.writeln('<h2>${_e(section.heading)}</h2>');
      for (final block in section.blocks) {
        final bullets = block.bullets;
        if (bullets != null) {
          body.writeln('<ul>');
          for (final item in bullets) {
            body.writeln('  <li>${_linkify(item)}</li>');
          }
          body.writeln('</ul>');
        } else {
          body.writeln('<p>${_linkify(block.text!)}</p>');
        }
      }
    }
    return _shell('${doc.title} · ${LegalInfo.appName}', body.toString());
  }

  static String _index() {
    final links = LegalContent.all
        .map((d) => '<li><a href="/${d.slug}">${_e(d.title)}</a></li>')
        .join('\n');
    return _shell(
      LegalInfo.appName,
      '<h1>${_e(LegalInfo.appName)}</h1>\n'
      '<p>A faith-based outreach app by '
      '${_e(LegalInfo.operatorName)}.</p>\n<ul>\n$links\n</ul>\n',
    );
  }

  static String _shell(String title, String body) =>
      '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_e(title)}</title>
<style>
:root { --bg: #ffffff; --text: #1e293b; --muted: #64748b; --accent: #0b2a4a; --line: #e2e8f0; }
@media (prefers-color-scheme: dark) {
  :root { --bg: #0f172a; --text: #e2e8f0; --muted: #94a3b8; --accent: #93c5fd; --line: #1e293b; }
}
body { margin: 0; background: var(--bg); color: var(--text);
  font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
main { max-width: 760px; margin: 0 auto; padding: 32px 16px 64px; }
h1 { color: var(--accent); font-size: 28px; margin: 0 0 4px; }
h2 { color: var(--accent); font-size: 19px; margin: 32px 0 8px; padding-top: 16px; border-top: 1px solid var(--line); }
.meta { color: var(--muted); margin-top: 0; }
a { color: var(--accent); overflow-wrap: anywhere; }
li { margin: 6px 0; }
footer { color: var(--muted); font-size: 14px; margin-top: 48px; }
</style>
</head>
<body>
<main>
$body<footer>&copy; ${_e(LegalInfo.operatorName)} · <a href="mailto:${LegalInfo.contactEmail}">${LegalInfo.contactEmail}</a></footer>
</main>
</body>
</html>
''';

  static String _e(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static final _links = RegExp(r'https://[^\s)]+[^\s).,]|[\w.+-]+@[\w-]+\.\w+');

  /// Escapes [s] and turns URLs and email addresses into links.
  static String _linkify(String s) {
    final out = StringBuffer();
    var last = 0;
    for (final m in _links.allMatches(s)) {
      out.write(_e(s.substring(last, m.start)));
      final v = m.group(0)!;
      final href = v.contains('@') && !v.startsWith('http') ? 'mailto:$v' : v;
      out.write('<a href="${_e(href)}">${_e(v)}</a>');
      last = m.end;
    }
    out.write(_e(s.substring(last)));
    return out.toString();
  }
}
