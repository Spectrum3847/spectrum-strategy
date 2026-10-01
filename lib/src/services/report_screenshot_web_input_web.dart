import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class WebPickedFile {
  const WebPickedFile({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

Future<WebPickedFile?> pickImageViaWebInput(List<String> extensions) {
  final completer = Completer<WebPickedFile?>();
  var settled = false;
  Timer? cancelTimer;

  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = extensions.map((ext) => '.$ext').join(',')
    ..style.display = 'none';

  late final JSFunction onFocus;

  void stopWaitingForFocus() {
    cancelTimer?.cancel();
    web.window.removeEventListener('focus', onFocus);
  }

  void finish(WebPickedFile? result) {
    if (settled) return;
    settled = true;
    stopWaitingForFocus();
    input.remove();
    if (!completer.isCompleted) completer.complete(result);
  }

  void fail(Object error) {
    if (settled) return;
    settled = true;
    stopWaitingForFocus();
    input.remove();
    if (!completer.isCompleted) completer.completeError(error);
  }

  void handleChange(web.Event _) async {
    stopWaitingForFocus();
    final file = input.files?.item(0);
    if (file == null) {
      finish(null);
      return;
    }
    try {
      final buffer = await file.arrayBuffer().toDart;
      finish(
        WebPickedFile(bytes: buffer.toDart.asUint8List(), name: file.name),
      );
    } catch (e) {
      fail(e);
    }
  }

  void handleCancel(web.Event _) => finish(null);

  void handleFocus(web.Event _) {
    web.window.removeEventListener('focus', onFocus);
    cancelTimer = Timer(const Duration(milliseconds: 500), () => finish(null));
  }

  final onChange = handleChange.toJS;
  final onCancel = handleCancel.toJS;
  onFocus = handleFocus.toJS;

  input.addEventListener('change', onChange);
  input.addEventListener('cancel', onCancel);
  web.window.addEventListener('focus', onFocus);

  web.document.body?.append(input);
  input.click();

  return completer.future;
}
