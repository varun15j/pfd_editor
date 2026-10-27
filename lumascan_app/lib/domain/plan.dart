/// The plans a user can be on. Basic is free; Pro and Gold are paid, and
/// Gold includes everything in Pro.
enum AppPlan {
  basic('Basic'),
  pro('Pro'),
  gold('Gold');

  const AppPlan(this.label);

  final String label;

  /// Whether this plan includes [feature].
  bool includes(PlanFeature feature) => index >= feature.minimum.index;
}

/// What a plan can switch on. Each feature names the lowest plan with it.
enum PlanFeature {
  /// The smarter scanning of Pro: page detection by colour, edge contrast
  /// and the middle of the frame; auto crop of every photo; the held-page
  /// repeat check; faster auto capture after a page turn; Auto crop and Full
  /// photo for many pages at once. Basic scans the original way.
  smartScan(AppPlan.pro),

  /// Text PDF: OCR turns a draft, or a saved PDF, into a PDF of real text
  /// with the pictures kept as images. Offered in the export sheet and the
  /// Library menu.
  textPdf(AppPlan.pro),

  /// PDF to Word: a saved PDF, a PDF from the device or the pages of a scan
  /// become a Word (.docx) file. Offered in Export, Tools and the Library
  /// menu. Word to PDF stays on every plan.
  word(AppPlan.pro),

  /// Auto mask: on-device OCR finds Aadhaar, VID, PAN and other ID numbers on
  /// a page and hides all but their last four characters. Drawing a mask by
  /// hand stays on every plan, because hiding your own ID number is basic
  /// privacy (Varun, 2026-10-26).
  autoMask(AppPlan.pro),

  /// Exported PDFs without the "Scanned with" mark that Basic
  /// prints at the foot of each page (Varun, 2026-10-27).
  noWatermark(AppPlan.pro),

  /// Page numbers ("2 / 5") at the foot of each page, offered as a switch
  /// in the export sheet.
  pageNumbers(AppPlan.pro),

  /// Signature library: signatures and initials saved once and placed again
  /// with a tap, plus date and name stamps, in the PDF editor and Markup.
  /// Drawing a one-off signature stays on every plan.
  signatureLibrary(AppPlan.pro),

  /// Table to Excel: one photo of a table becomes an Excel (.xlsx) file.
  /// The table is read with on-device OCR, so it costs nothing per use and
  /// needs no usage cap; it is Gold because rivals sell it at their top
  /// tier (improvement.md #21).
  tableToExcel(AppPlan.gold),

  /// Compress to a target size: a copy of a saved PDF made to fit under
  /// 200 KB, 500 KB, 1 MB or 2 MB for upload forms, choosing resolution and
  /// quality automatically. Offered in the Send PDF sheet.
  targetSize(AppPlan.pro),

  /// Document password: a copy of a saved PDF, encrypted with AES-256, that
  /// asks for a password when opened. Offered in the Library menu and the
  /// Send sheet.
  password(AppPlan.pro),

  /// Split a PDF into several by page ranges, or extract chosen pages into
  /// a new PDF. Offered in Tools and the Library menu; merging stays on
  /// every plan.
  splitPdf(AppPlan.pro),

  /// Text recognition in Indian languages: Hindi, Marathi and the other
  /// Devanagari languages including neat handwriting, and Bangla, Gujarati,
  /// Tamil, Telugu, Kannada, Malayalam, Punjabi, Odia, Assamese and Urdu.
  /// Basic reads English and other Latin-script languages.
  indianOcr(AppPlan.pro),

  /// Auto file naming: the save sheet suggests a name from the text on the
  /// first page, such as "Invoice INV-2041 2026-10-26", instead of the date
  /// pattern. Read on the device; typing a name stays on every plan.
  smartName(AppPlan.pro);

  const PlanFeature(this.minimum);

  final AppPlan minimum;
}
