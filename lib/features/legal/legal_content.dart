// Pure Dart (no Flutter imports): also used by tool/build_legal_pages.dart
// to generate the public web pages.

import 'package:gps_cielo/core/config/app_config.dart';
import 'package:gps_cielo/features/legal/legal_info.dart';

/// A paragraph, or a bulleted list when [bullets] is set.
class LegalBlock {
  final String? text;
  final List<String>? bullets;

  const LegalBlock.p(String this.text) : bullets = null;
  const LegalBlock.list(List<String> this.bullets) : text = null;
}

class LegalSection {
  final String heading;
  final List<LegalBlock> blocks;

  const LegalSection(this.heading, this.blocks);
}

class LegalDocument {
  /// URL-safe name, e.g. `privacy` (also the web page's file name).
  final String slug;
  final String title;
  final String intro;
  final List<LegalSection> sections;

  const LegalDocument({
    required this.slug,
    required this.title,
    required this.intro,
    required this.sections,
  });

  String get lastUpdated => 'Last updated: ${LegalInfo.effectiveDate}';
}

abstract final class LegalContent {
  static const _app = LegalInfo.appName;
  static const _org = LegalInfo.operatorName;
  static const _email = LegalInfo.contactEmail;

  static const LegalDocument privacyPolicy = LegalDocument(
    slug: 'privacy',
    title: 'Privacy Policy',
    intro:
        'This Privacy Policy explains how $_org ("$_org", "we", "us") '
        'collects, uses, shares and protects information when you use the '
        '$_app mobile app (the "App"). By using the App you agree to this '
        'policy. If you do not agree, please do not use the App.',
    sections: [
      LegalSection('1. Who we are', [
        LegalBlock.p(
          '$_app is a faith-based outreach app provided by $_org, a '
          'fellowship of churches in the United States '
          '(${LegalInfo.operatorWebsite}). We are responsible for the '
          'information described in this policy. You can reach us at '
          '$_email or ${LegalInfo.mailingAddress}.',
        ),
      ]),
      LegalSection('2. Information you give us', [
        LegalBlock.list([
          'Account details: your name, email address and password. Your '
              'password is handled by Google Firebase Authentication; we '
              'never see or store it.',
          if (AppConfig.phoneAuthEnabled)
            'Phone number (optional): if you add one, it is verified by a '
                'text message code and can then be used to sign in or reset '
                'your password.',
          'Profile details: profile photo, church affiliation, home address '
              'and the home location you save, and your prayer preferences '
              '(daily goal, cycle goal, number of homes and search range).',
          'Outreach activity: the households you mark as prayed for, '
              'visited or invited, follow-up dates, and any notes or '
              'resident names you choose to enter.',
          'Support messages: what you write to us through Contact Support, '
              'together with your account email.',
        ]),
      ]),
      LegalSection('3. Sign in with Google or Apple', [
        LegalBlock.p(
          'If you sign in with Google or Apple, that provider shares your '
          'name, email address and an account identifier with us. With Sign '
          'in with Apple you may choose to hide your email; we then receive '
          'a private relay address from Apple. We do not receive your Google '
          'or Apple password.',
        ),
      ]),
      LegalSection('4. Location', [
        LegalBlock.p(
          'With your permission, the App reads your device\'s precise '
          'location only while you are using it, when you choose to use your '
          'current location, to set your home location and show households '
          'near you. The App does not track your location in the background '
          'and we do not keep a history of your movements. We store only the '
          'home location and address you save. You can turn off location '
          'access at any time in your device settings and enter an address '
          'instead.',
        ),
      ]),
      LegalSection('5. Notifications and device information', [
        LegalBlock.p(
          'If you allow notifications, we store a push notification token '
          'for your device and its platform (iOS or Android) so we can send '
          'prayer reminders, follow-up reminders and ministry news. Your '
          'notifications are also kept in your in-app inbox. Signing out or '
          'deleting your account removes the token. Our service providers '
          'may also process technical data such as your IP address, device '
          'type and operating system version in order to run the service.',
        ),
      ]),
      LegalSection('6. Information about households and neighbors', [
        LegalBlock.p(
          'The App shows listings of nearby households so that members can '
          'pray for their neighbors. A listing contains a street address, an '
          'approximate map location and, in some cases, a resident or family '
          'name. Listings come from information we compile from publicly '
          'available sources and from participating churches. Your own '
          'notes, statuses and follow-ups about a household are private to '
          'your account; other users cannot see them.',
        ),
        LegalBlock.p(
          'Please enter only what is necessary for prayer and outreach, and '
          'never record sensitive details such as health, finances or '
          'immigration status. If you live at a listed address and would '
          'like it removed or corrected, email us at $_email and we will '
          'respond promptly.',
        ),
      ]),
      LegalSection('7. How we use information', [
        LegalBlock.list([
          'To create and secure your account and let you sign in.',
          'To show households near your home location and track your prayer '
              'and outreach progress.',
          'To send the notifications you allow.',
          'To answer your support messages.',
          'To keep the App safe, prevent abuse, fix problems and improve '
              'it.',
          'To comply with the law.',
        ]),
        LegalBlock.p(
          'We do not sell your personal information, we do not show '
          'advertising, and we do not track you across other companies\' '
          'apps or websites.',
        ),
      ]),
      LegalSection('8. Service providers we share with', [
        LegalBlock.p(
          'We share information only with providers that help us run the '
          'App, and only for that purpose:',
        ),
        LegalBlock.list([
          if (AppConfig.phoneAuthEnabled)
            'Google Firebase (Google LLC): sign-in, phone verification, '
                'database storage and push notifications.'
          else
            'Google Firebase (Google LLC): sign-in, database storage and push '
                'notifications.',
          'Google Sign-In and Sign in with Apple: if you choose them to sign '
              'in.',
          'OpenStreetMap Foundation: map images. Loading the map sends your '
              'IP address and the map area being viewed to its tile '
              'servers.',
          'Photon by komoot: address search. The text you type in an address '
              'field, or the coordinates being looked up, is sent to find '
              'matching addresses.',
        ]),
        LegalBlock.p(
          'We may also disclose information if required by law or a valid '
          'legal request, to protect the rights, safety or property of '
          'users, the public or $_org, or as part of a merger or transfer '
          'of the ministry, in which case this policy will continue to apply '
          'to your information.',
        ),
      ]),
      LegalSection('9. How long we keep information', [
        LegalBlock.p(
          'We keep your information for as long as your account exists. You '
          'can delete your account at any time in the App under Profile > '
          'Delete account. This permanently deletes your account, profile, '
          'outreach history and notes, notifications, device tokens and '
          'support messages. Copies may remain in secure backups for a '
          'limited time before being overwritten.',
        ),
      ]),
      LegalSection('10. Security', [
        LegalBlock.p(
          'Information is sent over encrypted connections and stored with '
          'Google Firebase, with access rules that let only you read and '
          'change your own data. No method of storage or transmission is '
          'completely secure, so we cannot guarantee absolute security. '
          'Please use a strong password and keep it private.',
        ),
      ]),
      LegalSection('11. Your choices and rights', [
        LegalBlock.list([
          'View and update your profile, address and preferences in the '
              'App at any time.',
          'Delete your account and data in the App.',
          'Turn location access or notifications on or off in your device '
              'settings.',
          'Ask us for a copy of your information, or to correct or delete '
              'it, by emailing $_email.',
        ]),
        LegalBlock.p(
          'Depending on where you live (for example California, other US '
          'states with privacy laws, the European Economic Area or the '
          'United Kingdom), you may have additional rights, such as to know '
          'what we collect, to access, correct, delete or export it, to '
          'object to or restrict certain uses, and to complain to a data '
          'protection authority. We will not treat you differently for '
          'using these rights. We may need to verify your identity before '
          'acting on a request.',
        ),
      ]),
      LegalSection('12. Children', [
        LegalBlock.p(
          'The App is not intended for children under '
          '${LegalInfo.minimumAge}, and we do not knowingly collect '
          'personal information from them. If you believe a child under '
          '${LegalInfo.minimumAge} has given us information, contact us at '
          '$_email and we will delete it.',
        ),
      ]),
      LegalSection('13. Where information is processed', [
        LegalBlock.p(
          'We are based in the United States, and our service providers may '
          'process information in the United States and other countries. '
          'Where required, they use legally recognized safeguards for '
          'international transfers.',
        ),
      ]),
      LegalSection('14. Changes to this policy', [
        LegalBlock.p(
          'We may update this policy from time to time. We will change the '
          '"Last updated" date above and, for significant changes, notify '
          'you in the App before they take effect.',
        ),
      ]),
      LegalSection('15. Contact us', [
        LegalBlock.p(
          'Questions or requests about your privacy: $_email, or '
          '$_org, ${LegalInfo.mailingAddress}.',
        ),
      ]),
    ],
  );

  static const LegalDocument termsOfUse = LegalDocument(
    slug: 'terms',
    title: 'Terms of Use',
    intro:
        'These Terms of Use ("Terms") are an agreement between you and '
        '$_org ("$_org", "we", "us") for your use of the $_app mobile '
        'app (the "App"). By creating an account or using the App you '
        'accept these Terms and our Privacy Policy. If you do not agree, do '
        'not use the App.',
    sections: [
      LegalSection('1. About the App', [
        LegalBlock.p(
          '$_app helps believers pray for the households around them, keep '
          'track of visits, invitations and follow-ups, and connect '
          'neighbors with the local church. The App is offered free of '
          'charge.',
        ),
      ]),
      LegalSection('2. Who may use the App', [
        LegalBlock.p(
          'You must be at least ${LegalInfo.minimumAge} years old to use '
          'the App. If you are under the age of majority where you live, '
          'you may use the App only with the involvement of a parent or '
          'guardian.',
        ),
      ]),
      LegalSection('3. Your account', [
        LegalBlock.p(
          'Give accurate information when you create your account and keep '
          'it up to date. You are responsible for keeping your password '
          'safe and for what happens under your account. Tell us right away '
          'at $_email if you think someone else is using it. You can delete '
          'your account at any time in the App under Profile > Delete '
          'account.',
        ),
      ]),
      LegalSection('4. Respecting your neighbors', [
        LegalBlock.p(
          'The App exists to serve neighbors with love and respect. When '
          'using it you agree to:',
        ),
        LegalBlock.list([
          'Treat every household with kindness and respect, and honor any '
              'request not to be contacted again.',
          'Never trespass, enter private property without permission, or '
              'visit at unreasonable hours.',
          'Never harass, threaten, pressure or discriminate against anyone.',
          'Keep notes brief and limited to prayer and outreach, and never '
              'record sensitive information such as health, finances, '
              'immigration status or other private matters.',
          'Not share household information from the App outside your '
              'ministry\'s outreach, or use it for any commercial, political '
              'or unlawful purpose.',
          'Follow all applicable laws and local rules, including those on '
              'door-to-door visits.',
        ]),
      ]),
      LegalSection('5. Acceptable use', [
        LegalBlock.p('You agree not to:'),
        LegalBlock.list([
          'Copy, scrape or collect household or user data from the App in '
              'bulk.',
          'Access the App or its systems other than through the App, or try '
              'to get around its security or access rules.',
          'Interfere with the App, introduce malware, or overload its '
              'services.',
          'Impersonate another person or misrepresent your connection with a '
              'church or ministry.',
          'Use the App to send spam or unwanted messages.',
        ]),
      ]),
      LegalSection('6. Household information', [
        LegalBlock.p(
          'Household listings are compiled from publicly available sources '
          'and participating churches and are provided for prayer and '
          'outreach only. They may be incomplete, out of date or inaccurate, '
          'and they do not say anything about the people who live there. '
          'Residents can ask for a listing to be corrected or removed by '
          'emailing $_email.',
        ),
      ]),
      LegalSection('7. Your content', [
        LegalBlock.p(
          'You keep ownership of the notes, messages, photos and other '
          'content you add ("Your Content"). You give us a limited, '
          'non-exclusive, royalty-free license to store and process Your '
          'Content only to run the App for you. You are responsible for '
          'Your Content and confirm you have the right to provide it. We '
          'may remove content that breaks these Terms.',
        ),
      ]),
      LegalSection('8. Notifications', [
        LegalBlock.p(
          'If you allow notifications, we may send reminders and ministry '
          'messages. You can turn them off at any time in your device '
          'settings.',
        ),
      ]),
      LegalSection('9. Our rights in the App', [
        LegalBlock.p(
          'The App, its design, text, graphics, logos and software belong to '
          '$_org or its licensors. We give you a personal, revocable, '
          'non-transferable, non-exclusive license to use the App on devices '
          'you own or control, for its intended ministry purpose, under '
          'these Terms. Maps use data from OpenStreetMap contributors, '
          'available under the Open Database License.',
        ),
      ]),
      LegalSection('10. Third-party services', [
        LegalBlock.p(
          'The App relies on services from others, such as Google, Apple, '
          'OpenStreetMap and Photon by komoot. Your use of those '
          'services may also be governed by their own terms, and we are not '
          'responsible for them.',
        ),
      ]),
      LegalSection('11. Suspension and termination', [
        LegalBlock.p(
          'You may stop using the App and delete your account at any time. '
          'We may suspend or close an account that breaks these Terms, puts '
          'others at risk, or harms the ministry. We may change, pause or '
          'discontinue all or part of the App, and will try to give notice '
          'of significant changes.',
        ),
      ]),
      LegalSection('12. Disclaimers', [
        LegalBlock.p(
          'The App is provided "as is" and "as available". To the fullest '
          'extent allowed by law, we disclaim all warranties, express or '
          'implied, including fitness for a particular purpose and '
          'non-infringement. We do not promise that the App will always be '
          'available, error-free or secure, or that household information '
          'is accurate. You are responsible for your own safety and conduct '
          'when visiting anyone.',
        ),
      ]),
      LegalSection('13. Limitation of liability', [
        LegalBlock.p(
          'To the fullest extent allowed by law, $_org and its officers, '
          'volunteers and partner churches will not be liable for any '
          'indirect, incidental, special, consequential or punitive damages, '
          'or for loss of data, arising from your use of the App. Our total '
          'liability for any claim relating to the App is limited to the '
          'greater of the amount you paid to use the App (which is zero) or '
          'US \$100. Some places do not allow these limits, so they may not '
          'apply to you.',
        ),
      ]),
      LegalSection('14. Indemnity', [
        LegalBlock.p(
          'You agree to defend and hold harmless $_org from claims and '
          'costs arising from your breach of these Terms or your conduct '
          'toward others while using the App.',
        ),
      ]),
      LegalSection('15. Governing law', [
        LegalBlock.p(
          'These Terms are governed by the laws of the State of '
          '${LegalInfo.governingState}, United States, without regard to '
          'conflict-of-law rules. Disputes will be resolved in the state or '
          'federal courts located in ${LegalInfo.venueCounty}, '
          '${LegalInfo.governingState}, unless the law where you live gives '
          'you the right to bring a claim locally. Before filing a claim, '
          'please contact us so we can try to resolve it informally.',
        ),
      ]),
      LegalSection('16. Apple App Store', [
        LegalBlock.p(
          'If you downloaded the App from the Apple App Store: these Terms '
          'are between you and $_org only, not Apple, and $_org, not Apple, '
          'is responsible for the App and its content. Apple has no '
          'obligation to provide maintenance or support. If the App fails '
          'to meet an applicable warranty, you may notify Apple, which may '
          'refund the purchase price (if any); Apple has no other warranty '
          'obligation. Apple is not responsible for any product liability, '
          'legal compliance or intellectual-property claims relating to the '
          'App. You confirm that you are not located in a country subject '
          'to a US government embargo or on a US list of prohibited or '
          'restricted parties. Apple and its subsidiaries are third-party '
          'beneficiaries of these Terms and may enforce them. Your use of '
          'the App must also follow the App Store Terms of Service.',
        ),
      ]),
      LegalSection('17. Changes to these Terms', [
        LegalBlock.p(
          'We may update these Terms from time to time. We will change the '
          '"Last updated" date above and, for significant changes, notify '
          'you in the App. Continuing to use the App after changes take '
          'effect means you accept them.',
        ),
      ]),
      LegalSection('18. Contact us', [
        LegalBlock.p(
          'Questions about these Terms: $_email, or $_org, '
          '${LegalInfo.mailingAddress}.',
        ),
      ]),
    ],
  );

  static const List<LegalDocument> all = [privacyPolicy, termsOfUse];
}
