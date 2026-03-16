// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

// ─── JS interop declarations ──────────────────────────────────────────────────

@JS('navigator.canShare')
external bool _canShare(JSObject shareData);

@JS('navigator.share')
external JSPromise _share(JSObject shareData);

// ─── Main entry point ─────────────────────────────────────────────────────────

Future<void> downloadFile(String url, String fileName) async {
  final ua = html.window.navigator.userAgent.toLowerCase();
  final isIos = ua.contains('iphone') ||
      ua.contains('ipad') ||
      ua.contains('ipod');

  if (isIos) {
    await _iosShare(url, fileName);
    return;
  }

  // Desktop / Android: standard anchor-click download
  _anchorDownload(url, fileName);
}

// ─── iOS: Web Share API ───────────────────────────────────────────────────────
// Triggers the native iOS share sheet so the user can choose
// "Save to Files", "Add to iCloud Drive", Google Drive, etc.

Future<void> _iosShare(String url, String fileName) async {
  try {
    // 1. Fetch the file as bytes
    final response = await web.window.fetch(url.toJS).toDart;
    final arrayBuffer = await response.arrayBuffer().toDart;
    final bytes = arrayBuffer.toDart.asUint8List();

    // 2. Create a Blob with the correct MIME type
    final mime = _mimeFromName(fileName);
    final blobParts = <JSAny>[bytes.toJS].toJS;
    final blobOptions = web.BlobPropertyBag(type: mime);
    final blob = web.Blob(blobParts, blobOptions);

    // 3. Create a File from the Blob
    final fileParts = <JSAny>[blob].toJS;
    final fileOptions = web.FilePropertyBag(type: mime);
    final file = web.File(fileParts, fileName, fileOptions);

    // 4. Build the shareData object with the file
    final filesArray = <JSAny>[file].toJS;
    final shareData = _buildShareData(filesArray, fileName);

    // 5. Check if the browser supports sharing files
    bool canShare = false;
    try {
      canShare = _canShare(shareData);
    } catch (_) {
      canShare = false;
    }

    if (canShare) {
      try {
        await _share(shareData).toDart;
        return; // User interacted with share sheet — done
      } catch (e) {
        final errStr = e.toString();
        // AbortError = user cancelled — that's fine, don't fallback
        if (errStr.contains('AbortError') ||
            errStr.contains('cancel') ||
            errStr.contains('abort')) {
          return;
        }
        // Other error — fall through to QuickLook fallback
      }
    }
  } catch (_) {
    // Fetch or File construction failed — fall through to QuickLook
  }

  // Fallback: open in new tab (iOS QuickLook preview)
  _openInNewTab(url);
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

JSObject _buildShareData(JSArray<JSAny> files, String title) {
  // We build the shareData object via JS eval because Dart's jsify
  // doesn't easily handle File arrays in a way navigator.share accepts.
  final obj = <String, dynamic>{
    'files': files,
    'title': title,
  };
  return obj.jsify()! as JSObject;
}

void _openInNewTab(String url) {
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('target', '_blank')
    ..setAttribute('rel', 'noopener noreferrer');
  html.document.body?.append(anchor);
  anchor.click();
  Future.delayed(const Duration(milliseconds: 150), anchor.remove);
}

void _anchorDownload(String url, String fileName) {
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName);
  html.document.body?.append(anchor);
  anchor.click();
  Future.delayed(const Duration(milliseconds: 150), anchor.remove);
}

String _mimeFromName(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  const map = {
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'txt': 'text/plain',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  };
  return map[ext] ?? 'application/octet-stream';
}

// Extension to convert Dart ByteBuffer to Uint8List
extension on ByteBuffer {
  Uint8List asUint8List() => Uint8List.view(this);
}
