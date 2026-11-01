import '../app/app_info.dart';

/// Version of the End User Licence Agreement below. Raise it by one whenever
/// the text changes in a way people must agree to again: everyone who
/// accepted an older version sees the agreement again at the next start and
/// cannot use the app until they accept it. Typo fixes can keep the number.
const eulaVersion = 1;

/// Date the current version takes effect, shown at the top of the agreement.
const eulaEffectiveDate = '30 October 2026';

// To be filled in (and the whole text checked) by a lawyer before release.
const _publisher = '[Publisher legal name]';
const _address = '[Registered address]';
const _contactEmail = '[support email]';
const _grievanceOfficer = '[Grievance Officer name]';
const _courtsCity = '[City]';

/// One numbered part of the agreement. Paragraphs are separated by a blank
/// line; lines starting with "• " are list items.
class EulaSection {
  const EulaSection(this.heading, this.body);
  final String heading;
  final String body;
}

/// What the agreement opens with, before the numbered parts.
const eulaIntro =
    'This End User Licence Agreement ("Agreement") is a legal agreement between you and $_publisher '
    '("we", "us") for the $appName mobile app, including its updates, features and any content we provide in it '
    '(the "App").\n\n'
    'By tapping "Agree and continue", or by using the App, you accept this Agreement. If you do not agree, '
    'do not use the App.';

const eulaSections = <EulaSection>[
  EulaSection(
    'Who can use the App',
    'You must be at least 18 years old, or use the App with the consent and supervision of a parent or legal '
        'guardian who accepts this Agreement for you. If you use the App for an organisation, you confirm that you '
        'may accept this Agreement for it.',
  ),
  EulaSection(
    'Licence',
    'We give you a personal, limited, non-exclusive, non-transferable and revocable licence to install and use '
        'the App on devices you own or control, for your personal use or the internal use of your business, as '
        'allowed by this Agreement and by the rules of the app store you got it from (Google Play or the Apple App '
        'Store).\n\n'
        'The App is licensed to you, not sold. We and our licensors keep all rights not expressly given to you.',
  ),
  EulaSection(
    'What you must not do',
    'You agree not to:\n'
        '• copy, modify, sell, rent, lend or redistribute the App;\n'
        '• reverse engineer, decompile or disassemble the App, except where the law allows it despite this term;\n'
        '• get around plan limits, payments, watermarks, passwords or other protection in the App;\n'
        '• use the App to scan, copy or share material you have no right to, such as copyrighted books or '
        'another person\'s identity documents without their permission;\n'
        '• use the App for anything unlawful, fraudulent or harmful, including forging documents or signatures.',
  ),
  EulaSection(
    'Your documents',
    'The photos, scans, PDFs, text, signatures and other content you create or bring into the App ("Your '
        'Content") stay yours. We claim no ownership of Your Content.\n\n'
        'The App works on your device. Your Content is kept on your device and leaves it only when you choose to '
        'share or export it, or when you connect a cloud storage account and send files to it. Files sent to such '
        'an account are handled under that provider\'s terms, not ours.\n\n'
        'You are responsible for Your Content, for having the right to scan and share it, and for keeping your '
        'own backups. Deleting the App, clearing its data or losing your device can delete Your Content for good, '
        'and we cannot recover it.',
  ),
  EulaSection(
    'Camera, photos and other permissions',
    'The App asks for access to your camera to scan, and to your photos or files when you import or save them. '
        'It uses these only for the feature you are using. You can turn a permission off in your device settings '
        'at any time; some features will then stop working.',
  ),
  EulaSection(
    'Automatic features and text recognition',
    'Edge detection, auto crop, image filters, text recognition (OCR), smart file names, table to spreadsheet '
        'and similar features are automatic and can make mistakes, especially with poor light, handwriting or '
        'some languages and scripts. Always check the result before you rely on it, in particular for legal, '
        'financial, medical or official documents.',
  ),
  EulaSection(
    'Signatures, passwords and app lock',
    'Signatures and stamps you add are images placed on the page. The App does not check who signed or create '
        'a certified digital signature, and whether a signed document is legally valid depends on the law that '
        'applies to it.\n\n'
        'If you protect a document with a password or lock the App, keep your password safe. We do not store it '
        'and cannot recover it or the document if it is lost.',
  ),
  EulaSection(
    'Plans, purchases and subscriptions',
    'The App has a free Basic plan and paid Pro and Gold plans. Exports on the Basic plan carry a small '
        '"$exportWatermark" mark. What each plan includes is shown in the App before you buy and may change over '
        'time.\n\n'
        'Paid plans are bought through Google Play or the Apple App Store, and their terms govern payment, '
        'renewal, cancellation and refunds. Subscriptions renew automatically until you cancel them in your store '
        'account, at least 24 hours before the current period ends. Prices are shown in the App and the store, '
        'including any applicable taxes such as GST.\n\n'
        'Nothing in this Agreement limits refunds or other rights you have under the Consumer Protection Act, '
        '2019 or other law that cannot be excluded.',
  ),
  EulaSection(
    'Privacy',
    'We collect as little as we can. Your documents are not sent to us. If you agree to share anonymous usage '
        'data, it covers things like which features are used and where the App fails, never your documents, '
        'pages or file names, and you can turn it off in Settings. Our Privacy Policy explains this in full, and '
        'we handle personal data as required by the Digital Personal Data Protection Act, 2023 and other law that '
        'applies.',
  ),
  EulaSection(
    'Updates and changes to this Agreement',
    'We may update the App to add, change or remove features, fix problems or follow the law. Some updates may '
        'be needed to keep using the App.\n\n'
        'We may also change this Agreement. When we do, the App shows you the new version, and you need to accept '
        'it to keep using the App. If you do not accept it, stop using the App and uninstall it.',
  ),
  EulaSection(
    'Other software and services',
    'The App includes open-source software, used under its own licences, which are listed in Settings under '
        'Open-source licences. Third-party services you use through the App, such as app stores or cloud storage, '
        'are governed by their own terms.',
  ),
  EulaSection(
    'Ownership of the App',
    'The App, its design, code, name and logos belong to us or our licensors and are protected by intellectual '
        'property law. This Agreement does not give you any right to use our name or trademarks.',
  ),
  EulaSection(
    'No warranty',
    'To the extent the law allows, the App is provided "as is" and "as available", without warranties of any '
        'kind, whether express or implied, including fitness for a particular purpose. We do not promise that '
        'the App will be error-free, uninterrupted or that it will never lose data.',
  ),
  EulaSection(
    'Limit of liability',
    'To the extent the law allows, we are not liable for any indirect, incidental, special or consequential '
        'loss, or for lost data, documents, profits or business, arising from your use of the App. Our total '
        'liability to you for any claim about the App is limited to the amount you paid us for the App in the 12 '
        'months before the claim.\n\n'
        'Nothing in this Agreement limits liability that cannot be limited by law.',
  ),
  EulaSection(
    'Ending this Agreement',
    'You can end this Agreement at any time by uninstalling the App. We may end or suspend your licence if you '
        'break this Agreement. When it ends you must stop using the App. Sections on your documents, ownership, '
        'no warranty, limit of liability and governing law continue after it ends.',
  ),
  EulaSection(
    'Governing law',
    'This Agreement is governed by the laws of India. Courts at $_courtsCity have exclusive jurisdiction, '
        'without affecting any right you have as a consumer to bring a claim where you live.',
  ),
  EulaSection(
    'If you got the App from the Apple App Store',
    'This Agreement is between you and us only, not Apple. We, not Apple, are responsible for the App, its '
        'support and maintenance, and any claims about it, including product liability, legal compliance and '
        'intellectual property claims. If the App fails to meet a warranty that applies, you may tell Apple, and '
        'Apple will refund the price you paid for it, if any; Apple has no other warranty obligation. You confirm '
        'you are not in a country under a US Government embargo and are not on a US Government list of '
        'prohibited or restricted parties. Apple and its subsidiaries are third-party beneficiaries of this '
        'Agreement and may enforce it against you.',
  ),
  EulaSection(
    'Contact and grievances',
    'Questions, complaints or notices about the App or this Agreement:\n'
        '$_publisher, $_address\n'
        'Email: $_contactEmail\n\n'
        'Grievance Officer (under the Information Technology Act, 2000 and its rules): $_grievanceOfficer, '
        '$_contactEmail. We acknowledge complaints within 24 hours and aim to resolve them within 15 days.',
  ),
];
