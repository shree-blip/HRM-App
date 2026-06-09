/// Helpers for Google Drive share links (ports the web lib/driveLinks.ts).
/// Documents store a Drive link instead of an uploaded file.
library;

const kDriveLinkHelperText =
    'Paste a Google Drive share link. Make sure the file is shared with the '
    'right person or set to anyone with the link.';

/// Extracts the Drive file id from common share-link formats.
String? _extractFileId(String url) {
  if (url.isEmpty) return null;
  final file = RegExp(r'/file/d/([^/]+)').firstMatch(url);
  if (file != null) return file.group(1);
  final id = RegExp(r'[?&]id=([^&]+)').firstMatch(url);
  if (id != null) return id.group(1);
  final doc = RegExp(r'/(?:document|spreadsheets|presentation)/d/([^/]+)').firstMatch(url);
  if (doc != null) return doc.group(1);
  return null;
}

/// Validates the pasted value is a Google Drive / Docs link.
bool isValidDriveLink(String? url) {
  if (url == null) return false;
  final t = url.trim();
  return RegExp(r'^https?://', caseSensitive: false).hasMatch(t) &&
      (RegExp(r'drive\.google\.com', caseSensitive: false).hasMatch(t) ||
          RegExp(r'docs\.google\.com', caseSensitive: false).hasMatch(t));
}

/// The URL that opens the Drive item directly.
String getDriveOpenUrl(String? url) => url?.trim() ?? '';

/// A URL suitable for an inline (iframe/WebView) preview.
String getDrivePreviewUrl(String? url) {
  final t = url?.trim() ?? '';
  if (t.isEmpty) return '';
  final fileId = _extractFileId(t);

  if (RegExp(r'docs\.google\.com', caseSensitive: false).hasMatch(t)) {
    if (RegExp(r'/(document|spreadsheets|presentation)/d/').hasMatch(t)) {
      return t
          .replaceAll(RegExp(r'/(edit|view)(\?[^#]*)?(#.*)?$', caseSensitive: false), '/preview')
          .replaceAll(RegExp(r'/$'), '');
    }
    return t;
  }
  if (fileId != null) {
    return 'https://drive.google.com/file/d/$fileId/preview';
  }
  return t;
}
