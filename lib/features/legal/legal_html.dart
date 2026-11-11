// Pure Dart: renders the public website for Firebase Hosting (home, support,
// account deletion, and the legal documents). See
// tool/build_legal_pages.dart and legal_site/.
//
// Everything here describes what the app actually does; keep it in step with
// the code (account deletion: UserRepository.deleteUserData and
// AuthService.deleteAccount).

import 'package:gps_cielo/features/legal/legal_content.dart';
import 'package:gps_cielo/features/legal/legal_info.dart';

abstract final class LegalHtml {
  static const String _app = LegalInfo.appName;
  static const String _org = LegalInfo.operatorName;
  static const String _email = LegalInfo.contactEmail;

  /// File name → page contents for every HTML file in `legal_site/`.
  static Map<String, String> site() => {
    'index.html': _home(),
    'support.html': _support(),
    'delete-account.html': _deleteAccount(),
    for (final doc in LegalContent.all) '${doc.slug}.html': page(doc),
    '404.html': _notFound(),
  };

  // ---------------------------------------------------------------- legal

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
    return _shell(
      title: '${doc.title} · $_app',
      description: '${doc.title} for the $_app app by $_org.',
      current: '/${doc.slug}',
      body: '<article class="doc">\n$body</article>\n',
    );
  }

  // ----------------------------------------------------------------- home

  static const List<(String, String, String)> _features = [
    (
      '&#x1F3E0;',
      'Your neighborhood',
      'Save your home address and see the households nearest to you, on a '
          'list and on a map.',
    ),
    (
      '&#x1F64F;',
      'Pray by name',
      'Pray for each family on your street and mark them as prayed for.',
    ),
    (
      '&#x1F3AF;',
      'Daily goals and rounds',
      'Set a daily prayer goal and follow your progress until every '
          'neighbor has been prayed for, then start a new round.',
    ),
    (
      '&#x1F6AA;',
      'Visits and invitations',
      'Record the homes you have visited or invited to church.',
    ),
    (
      '&#x1F4C5;',
      'Follow-ups and notes',
      'Schedule follow-up dates and keep private notes that only you can '
          'see.',
    ),
    (
      '&#x1F514;',
      'Notifications',
      'Receive reminders and ministry news, kept in an in-app inbox.',
    ),
  ];

  static String _home() {
    final features = _features
        .map(
          (f) =>
              '<div class="card"><div class="icon" aria-hidden="true">'
              '${f.$1}</div><h3>${_e(f.$2)}</h3><p>${_e(f.$3)}</p></div>',
        )
        .join('\n');
    return _shell(
      title: '$_app · Pray for your neighbors',
      description:
          '$_app helps believers pray for the households around them, '
          'record visits and invitations, and follow up with their '
          'neighbors.',
      current: '/',
      body:
          '''
<section class="hero">
  <img src="/logo.svg" alt="" width="72" height="85">
  <h1>$_app</h1>
  <p class="tagline">Conectando hogares, alcanzando vidas.</p>
  <p class="lead">A free app that helps believers pray for every household in
  their neighborhood by name, visit and invite their neighbors, and follow up
  so no one is forgotten.</p>
</section>

<h2>What you can do</h2>
<div class="grid">
$features
</div>

<h2>Getting started</h2>
<ol class="steps">
  <li>Create an account with your email, Google or Apple.</li>
  <li>Enter your home address, or use your current location.</li>
  <li>Choose your daily prayer goal and start praying for the homes around
  you.</li>
</ol>

<h2>About us</h2>
<p>$_app is provided by $_org (<a href="${LegalInfo.operatorWebsite}">gaccchurch.org</a>).</p>

<h2>Help and contact</h2>
<p>Questions or problems? Visit <a href="/support">Support</a> or email
<a href="mailto:$_email">$_email</a>.</p>
''',
    );
  }

  // -------------------------------------------------------------- support

  static const List<(String, String)> _faq = [
    (
      'How do I create an account or sign in?',
      'Open the app and choose Sign Up to create an account with your name, '
          'email and a password, or continue with Google or Apple. After '
          'that, use Sign In with the same method.',
    ),
    (
      'I forgot my password.',
      'On the Sign In screen tap "Forgot your password?", enter your email '
          'address and follow the link we email you to choose a new '
          'password. Check your spam folder if it does not arrive. If you '
          'signed up with Google or Apple, sign in with that button instead; '
          'there is no separate password.',
    ),
    (
      'Google or Apple sign-in does not work.',
      'Make sure you are connected to the internet and signed in to your '
          'Google account or Apple ID on the device, then try again. If you '
          'chose "Hide My Email" with Apple, your account uses the relay '
          'address Apple created, so keep using Sign in with Apple.',
    ),
    (
      'How does the app use my location?',
      'Only while you use the app, and only when you choose "Use my current '
          'location" to set your home location. The app never tracks you in '
          'the background. You can type your address instead.',
    ),
    (
      'I denied location access. How do I turn it back on?',
      'Open your device Settings, find GPS Cielo and allow location access '
          '"While Using the App". Or simply type your address on the Home '
          'screen.',
    ),
    (
      'No households appear near me.',
      'Check that your home address is correct (Profile > My address). '
          'Then increase the search range in Profile > Prayer preferences. '
          'Households are only shown where listings exist, so some areas may '
          'have none yet.',
    ),
    (
      'How do I change my neighborhood or how many homes I pray for?',
      'Go to Profile > Prayer preferences to set your daily prayer goal, '
          'the number of homes in your neighborhood and the search range. '
          'You can also search another place on the Home screen without '
          'changing your home address.',
    ),
    (
      'I do not receive notifications.',
      'Allow notifications for GPS Cielo in your device Settings and make '
          'sure you are signed in. Notifications you receive also appear in '
          'the inbox (the bell on the Home screen).',
    ),
    (
      'Who can see my notes and activity?',
      'Only you. Your notes, prayer and visit records and follow-ups are '
          'private to your account. See the Privacy Policy for details.',
    ),
  ];

  static String _support() {
    final faq = _faq
        .map(
          (q) =>
              '<details><summary>${_e(q.$1)}</summary>'
              '<p>${_e(q.$2)}</p></details>',
        )
        .join('\n');
    return _shell(
      title: 'Support · $_app',
      description: 'Help and contact for the $_app app.',
      current: '/support',
      body:
          '''
<h1>Support</h1>
<p class="lead">Need help with $_app? Find answers below or contact us.</p>

<div class="contact">
  <h2>Contact us</h2>
  <p>Email <a href="mailto:$_email">$_email</a>. Please include the email
  address you use in the app and, if possible, your device model.</p>
  <p>Signed-in users can also write to us from the app: Profile &gt;
  Contact support.</p>
</div>

<h2>Common questions</h2>
<div class="faq">
$faq
<details><summary>How do I delete my account?</summary>
<p>In the app go to Profile &gt; Delete account. See
<a href="/delete-account">Delete your account</a> for the steps and what is
deleted.</p></details>
</div>

<h2>Policies</h2>
<ul>
  <li><a href="/privacy">Privacy Policy</a></li>
  <li><a href="/terms">Terms of Use</a></li>
  <li><a href="/delete-account">Delete your account</a></li>
</ul>
''',
    );
  }

  // ------------------------------------------------------- delete account

  static String _deleteAccount() => _shell(
    title: 'Delete your account · $_app',
    description:
        'How to delete your $_app account and what happens to your data.',
    current: '/delete-account',
    body:
        '''
<h1>Delete your account</h1>
<p class="lead">You can permanently delete your $_app account and its data
at any time, directly in the app.</p>

<h2>Steps</h2>
<ol class="steps">
  <li>Open $_app and sign in.</li>
  <li>Go to the <strong>Profile</strong> tab.</li>
  <li>Scroll down and tap <strong>Delete account</strong>.</li>
  <li>Confirm who you are: enter your password if you use email sign-in, or
  confirm with Google or Apple if you signed in with them.</li>
  <li>Tap <strong>Delete</strong>. The app returns to the Sign In screen and
  shows "Account Deleted".</li>
</ol>

<h2>What is deleted</h2>
<ul>
  <li>Your sign-in account (email, Google or Apple login).</li>
  <li>Your profile: name, email, profile photo, church affiliation, home
  address and location, and prayer preferences.</li>
  <li>Your prayer, visit, invitation and follow-up records and your
  notes.</li>
  <li>Your in-app notifications and the push notification tokens for your
  devices.</li>
  <li>Messages you sent through Contact support.</li>
</ul>
<p>Deletion is permanent and cannot be undone. Data is removed from our
database right away; our service provider, Google, may take some time to
remove it completely from its systems.</p>

<h2>What is not deleted</h2>
<ul>
  <li>Household listings shown in the app. They are not part of your account
  and other users keep seeing them.</li>
  <li>Data held by Google or Apple for your own Google account or Apple ID,
  which you manage with them.</li>
</ul>

<h2>Can't open the app?</h2>
<p>Email <a href="mailto:$_email">$_email</a> from the address you use in the
app and ask us to delete your account. We may need to verify that the account
is yours before deleting it.</p>

<p>See also the <a href="/privacy">Privacy Policy</a>.</p>
''',
  );

  // ------------------------------------------------------------------ 404

  static String _notFound() => _shell(
    title: 'Page not found · $_app',
    description: 'Page not found.',
    current: '',
    body: '''
<h1>Page not found</h1>
<p>That page does not exist. Go to the <a href="/">home page</a> or
<a href="/support">Support</a>.</p>
''',
  );

  // ---------------------------------------------------------------- shell

  static const List<(String, String)> _nav = [
    ('/', 'Home'),
    ('/support', 'Support'),
    ('/privacy', 'Privacy'),
    ('/terms', 'Terms'),
    ('/delete-account', 'Delete account'),
  ];

  static String _shell({
    required String title,
    required String description,
    required String current,
    required String body,
  }) {
    final nav = _nav
        .map(
          (n) =>
              '<a href="${n.$1}"${n.$1 == current ? ' aria-current="page"' : ''}>'
              '${_e(n.$2)}</a>',
        )
        .join('');
    final year = LegalInfo.effectiveDate.split(' ').last;
    return '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_e(title)}</title>
<meta name="description" content="${_e(description)}">
<meta property="og:title" content="${_e(title)}">
<meta property="og:description" content="${_e(description)}">
<meta property="og:type" content="website">
<meta name="theme-color" content="#1B2A4A">
<link rel="icon" href="/logo.svg" type="image/svg+xml">
<style>
:root { --bg: #f8fafc; --surface: #ffffff; --text: #1e293b; --muted: #64748b;
  --navy: #1b2a4a; --gold: #a58133; --line: #e2e8f0; --link: #1b2a4a; }
@media (prefers-color-scheme: dark) {
  :root { --bg: #0f172a; --surface: #1e293b; --text: #e2e8f0; --muted: #94a3b8;
    --navy: #e2e8f0; --gold: #e2bc68; --line: #334155; --link: #93c5fd; }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text);
  font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
a { color: var(--link); overflow-wrap: anywhere; }
header { background: #1b2a4a; color: #fff; }
.bar { max-width: 960px; margin: 0 auto; padding: 12px 16px; display: flex;
  flex-wrap: wrap; align-items: center; gap: 8px 20px; }
.brand { color: #fff; text-decoration: none; font-weight: 700; letter-spacing: .3px;
  display: flex; align-items: center; gap: 8px; }
.brand img { width: 30px; height: 32px; padding: 3px 4px; background: #fff; border-radius: 8px; }
.brand span { color: #e2bc68; }
nav { display: flex; flex-wrap: wrap; gap: 4px 16px; font-size: 15px; }
nav a { color: #cbd5e1; text-decoration: none; padding: 4px 0; }
nav a:hover, nav a[aria-current="page"] { color: #fff; border-bottom: 2px solid #e2bc68; }
main { max-width: 960px; margin: 0 auto; padding: 32px 16px 56px; }
.doc { max-width: 760px; }
h1 { color: var(--navy); font-size: 30px; line-height: 1.25; margin: 0 0 8px; }
h2 { color: var(--navy); font-size: 21px; margin: 36px 0 10px; }
.doc h2 { font-size: 19px; padding-top: 16px; border-top: 1px solid var(--line); }
h3 { color: var(--navy); font-size: 17px; margin: 8px 0 4px; }
.meta { color: var(--muted); margin-top: 0; }
.lead { font-size: 18px; color: var(--muted); max-width: 680px; }
.hero { text-align: center; padding: 16px 0 8px; }
.hero h1 { font-size: 34px; margin-top: 12px; }
.hero .lead { margin: 8px auto 0; }
.tagline { color: var(--gold); font-weight: 600; margin: 0; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 16px; }
.card, .contact, details { background: var(--surface); border: 1px solid var(--line);
  border-radius: 14px; padding: 16px 18px; }
.card p { margin: 0; color: var(--muted); }
.icon { font-size: 26px; }
.steps li, li { margin: 6px 0; }
.contact h2 { margin-top: 0; }
.faq { display: grid; gap: 10px; }
details summary { cursor: pointer; font-weight: 600; color: var(--navy); }
details p { margin: 8px 0 0; }
footer { border-top: 1px solid var(--line); color: var(--muted); font-size: 14px; }
footer .bar { display: block; padding: 20px 16px 32px; }
footer nav a { color: var(--muted); }
footer nav a:hover { color: var(--text); border: 0; }
footer p { margin: 8px 0 0; }
</style>
</head>
<body>
<header><div class="bar">
<a class="brand" href="/"><img src="/logo.svg" alt="">GPS <span>Para El</span> Cielo</a>
<nav aria-label="Main">$nav</nav>
</div></header>
<main>
$body</main>
<footer><div class="bar">
<nav aria-label="Footer">$nav</nav>
<p>&copy; $year ${_e(_org)} · <a href="mailto:$_email">$_email</a></p>
</div></footer>
</body>
</html>
''';
  }

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
