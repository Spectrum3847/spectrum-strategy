import 'dart:js_interop';

import 'package:web/web.dart' as web;

const String _cachePrefix = 'spectrum-strategy-';

Future<void> clearCachedBuild() async {
  final registrations = await web.window.navigator.serviceWorker
      .getRegistrations()
      .toDart;
  for (final registration in registrations.toDart) {
    await registration.unregister().toDart;
  }
  final cacheNames = await web.window.caches.keys().toDart;
  for (final jsName in cacheNames.toDart) {
    final name = jsName.toDart;
    if (name.startsWith(_cachePrefix)) {
      await web.window.caches.delete(name).toDart;
    }
  }
  web.window.location.reload();
}
