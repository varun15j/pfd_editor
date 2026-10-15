import 'dart:io';

/// Cloud storage services the user can connect in Settings > Accounts to
/// import documents from. Read-only: nothing is uploaded or synced.
enum CloudProviderId {
  googleDrive('Google Drive'),
  oneDrive('Microsoft OneDrive'),
  iCloudDrive('iCloud Drive');

  const CloudProviderId(this.label);

  final String label;
}

/// What a cloud file can become in the Library.
enum CloudEntryKind {
  folder,
  pdf,
  word,

  /// A Google Docs document, which Drive exports as a PDF.
  googleDoc,
  other;

  bool get importable => this == pdf || this == word || this == googleDoc;
}

/// A folder or file in a cloud account.
class CloudEntry {
  const CloudEntry({required this.id, required this.name, required this.kind, this.sizeBytes, this.modifiedAt});

  final String id;
  final String name;
  final CloudEntryKind kind;
  final int? sizeBytes;
  final DateTime? modifiedAt;

  bool get isFolder => kind == CloudEntryKind.folder;

  /// The kind of file [name] names, judged by its extension.
  static CloudEntryKind kindForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return CloudEntryKind.pdf;
    if (lower.endsWith('.docx')) return CloudEntryKind.word;
    return CloudEntryKind.other;
  }
}

/// The signed-in account of a connected provider.
class CloudAccount {
  const CloudAccount({required this.name, this.email});

  final String name;
  final String? email;

  /// "Varun (varun@example.com)", or just the name or email when only one is
  /// known or both are the same.
  String get label {
    final e = email;
    if (e == null || e.isEmpty || e == name) return name;
    if (name.isEmpty) return e;
    return '$name ($e)';
  }
}

/// Whether a provider can be used on this phone and build.
enum CloudAvailability {
  ready,

  /// The OAuth client IDs in lib/app/cloud_config.dart are still placeholders.
  notConfigured,

  /// The service has no way in on this platform (iCloud Drive on Android).
  unsupportedPlatform,
}

/// A file the user picked through the system document picker, already copied
/// to a local path.
class PickedCloudFile {
  const PickedCloudFile({required this.name, required this.file});

  final String name;
  final File file;
}

/// Thrown when the user closes a sign-in or picker without finishing it.
class CloudCancelled implements Exception {
  const CloudCancelled();
}

/// Thrown when the service refuses a saved sign-in, so the user has to
/// connect again.
class CloudSignInExpired implements Exception {
  const CloudSignInExpired();

  @override
  String toString() => 'The sign-in has expired. Connect the account again.';
}

/// One cloud storage service. Each provider is its own class behind this
/// interface so screens and tests do not depend on any service's SDK.
///
/// A provider either browses through the service's API ([list] and
/// [download]) or, when [usesSystemPicker] is true, hands over to the system
/// document picker ([pickFile]), which is how apps reach iCloud Drive.
abstract class CloudStorageProvider {
  CloudProviderId get id;

  CloudAvailability get availability;

  /// True when files are chosen in the system picker instead of a browse
  /// screen, and there is no account to connect.
  bool get usesSystemPicker => false;

  /// The account signed in on an earlier visit, without showing any sign-in
  /// screen, or null when there is none.
  Future<CloudAccount?> restore();

  /// Signs in and asks for read-only access. Throws [CloudCancelled] when the
  /// user backs out.
  Future<CloudAccount> connect();

  /// Signs out and forgets the saved sign-in on this phone.
  Future<void> disconnect();

  /// Folders and files in [folderId], or in the top folder when null.
  /// Folders come first, then files, each by name.
  Future<List<CloudEntry>> list(String? folderId) => throw UnsupportedError('${id.label} has no browse screen');

  /// Downloads [entry] into [directory] and returns the local copy. A
  /// [CloudEntryKind.googleDoc] arrives as a PDF.
  Future<File> download(CloudEntry entry, Directory directory) =>
      throw UnsupportedError('${id.label} has no browse screen');

  /// Opens the system document picker for PDF and Word files. Returns null
  /// when the user closes it.
  Future<PickedCloudFile?> pickFile() => throw UnsupportedError('${id.label} has a browse screen');
}

/// Folders first, then files, each in name order ignoring case.
List<CloudEntry> sortCloudEntries(Iterable<CloudEntry> entries) => [...entries]
  ..sort((a, b) {
    if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
