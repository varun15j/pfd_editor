/// "850 KB" or "1.4 MB".
String formatFileSize(int bytes) =>
    bytes < 1024 * 1024 ? '${(bytes / 1024).round()} KB' : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
