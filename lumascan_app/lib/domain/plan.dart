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

  /// Compress to a target size: a copy of a saved PDF made to fit under
  /// 200 KB, 500 KB, 1 MB or 2 MB for upload forms, choosing resolution and
  /// quality automatically. Offered in the Send PDF sheet.
  targetSize(AppPlan.pro);

  const PlanFeature(this.minimum);

  final AppPlan minimum;
}

/// The plan every user is on until purchases exist. Billing will replace
/// this with the plan the store reports; until then, change it here to try
/// a plan in any build, or switch plans from the debug panel in debug builds.
const purchasedPlan = AppPlan.basic;
