/// The capture modes along the bottom of the camera (iOS flow prototype,
/// screen 02).
enum CameraMode {
  /// One page per photo, cropped to the page found in it.
  docs('Docs', 'Take photo', 'Tap the shutter for each page'),

  /// An open book: one photo makes a left and a right page.
  book('Book', 'Capture left and right book pages', 'Align the book spine with the line'),

  /// Reads the text in view and offers it to copy. No page is added unless
  /// asked for.
  text('Text', 'Capture recognized text', 'Point at text to recognize'),

  /// Like Docs, and the text on each page is read in the background so it
  /// can be copied or searched.
  ocrDoc('OCR Doc', 'Capture page for text recognition', 'Fill the frame with the page'),

  /// Reads a QR code. Nothing is opened without asking.
  qr('QR', 'Scan QR code', 'Place the QR code in the frame'),

  /// A plain photo: no crop and no page detection.
  photo('Photo', 'Take a plain photo', 'Compose your photo');

  const CameraMode(this.label, this.shutterLabel, this.guidance);

  final String label;

  /// Spoken label of the shutter in this mode.
  final String shutterLabel;

  /// Guidance shown over the preview when auto capture is not running.
  final String guidance;

  /// Modes whose photos become pages of the document.
  bool get addsPages => this != text && this != qr;

  /// Modes where auto capture can take the photo once a page is steady.
  bool get canAutoCapture => this == docs || this == book || this == ocrDoc;

  /// Modes that look for the page in each photo.
  bool get findsPage => this == docs || this == book || this == ocrDoc;
}
