/// Writing systems text recognition has to tell apart. A recognition model
/// reads one script, so the language picked decides which model runs.
enum OcrScript {
  latin('Latin'),
  devanagari('Devanagari'),
  bengali('Bengali'),
  gujarati('Gujarati'),
  gurmukhi('Gurmukhi'),
  odia('Odia'),
  tamil('Tamil'),
  telugu('Telugu'),
  kannada('Kannada'),
  malayalam('Malayalam'),
  arabic('Perso-Arabic');

  const OcrScript(this.label);
  final String label;
}

/// A language text recognition can be asked to read, with its name in
/// English and in its own script.
class OcrLanguage {
  const OcrLanguage(this.code, this.name, this.nativeName, this.script);

  /// BCP 47 code, such as `hi`.
  final String code;
  final String name;
  final String nativeName;
  final OcrScript script;

  /// Shown in pickers, like "Hindi · हिन्दी".
  String get label => name == nativeName ? name : '$name · $nativeName';

  /// English, then the scheduled Indian languages with a script of their own
  /// or a large reading population, then other Latin-script languages.
  static const all = [
    OcrLanguage('en', 'English', 'English', OcrScript.latin),
    OcrLanguage('hi', 'Hindi', 'हिन्दी', OcrScript.devanagari),
    OcrLanguage('mr', 'Marathi', 'मराठी', OcrScript.devanagari),
    OcrLanguage('bn', 'Bangla', 'বাংলা', OcrScript.bengali),
    OcrLanguage('gu', 'Gujarati', 'ગુજરાતી', OcrScript.gujarati),
    OcrLanguage('ta', 'Tamil', 'தமிழ்', OcrScript.tamil),
    OcrLanguage('te', 'Telugu', 'తెలుగు', OcrScript.telugu),
    OcrLanguage('kn', 'Kannada', 'ಕನ್ನಡ', OcrScript.kannada),
    OcrLanguage('ml', 'Malayalam', 'മലയാളം', OcrScript.malayalam),
    OcrLanguage('pa', 'Punjabi', 'ਪੰਜਾਬੀ', OcrScript.gurmukhi),
    OcrLanguage('or', 'Odia', 'ଓଡ଼ିଆ', OcrScript.odia),
    OcrLanguage('as', 'Assamese', 'অসমীয়া', OcrScript.bengali),
    OcrLanguage('ur', 'Urdu', 'اردو', OcrScript.arabic),
    OcrLanguage('ne', 'Nepali', 'नेपाली', OcrScript.devanagari),
    OcrLanguage('kok', 'Konkani', 'कोंकणी', OcrScript.devanagari),
    OcrLanguage('mai', 'Maithili', 'मैथिली', OcrScript.devanagari),
    OcrLanguage('sa', 'Sanskrit', 'संस्कृतम्', OcrScript.devanagari),
    OcrLanguage('de', 'German', 'Deutsch', OcrScript.latin),
    OcrLanguage('fr', 'French', 'Français', OcrScript.latin),
    OcrLanguage('es', 'Spanish', 'Español', OcrScript.latin),
    OcrLanguage('it', 'Italian', 'Italiano', OcrScript.latin),
    OcrLanguage('pt', 'Portuguese', 'Português', OcrScript.latin),
    OcrLanguage('nl', 'Dutch', 'Nederlands', OcrScript.latin),
    OcrLanguage('sv', 'Swedish', 'Svenska', OcrScript.latin),
    OcrLanguage('da', 'Danish', 'Dansk', OcrScript.latin),
    OcrLanguage('no', 'Norwegian', 'Norsk', OcrScript.latin),
    OcrLanguage('fi', 'Finnish', 'Suomi', OcrScript.latin),
    OcrLanguage('pl', 'Polish', 'Polski', OcrScript.latin),
    OcrLanguage('cs', 'Czech', 'Čeština', OcrScript.latin),
    OcrLanguage('tr', 'Turkish', 'Türkçe', OcrScript.latin),
    OcrLanguage('id', 'Indonesian', 'Bahasa Indonesia', OcrScript.latin),
  ];

  static final Map<String, OcrLanguage> _byCode = {for (final l in all) l.code: l};

  /// The language with [code], or null for a code LumaScan does not know.
  static OcrLanguage? byCode(String code) => _byCode[code];

  /// The language with [code], falling back to English.
  static OcrLanguage of(String code) => _byCode[code] ?? all.first;
}
