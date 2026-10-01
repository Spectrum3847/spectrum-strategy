import 'web_cache_reset_web.dart'
    if (dart.library.io) 'web_cache_reset_io.dart'
    as web_cache_reset;

Future<void> clearCachedBuild() => web_cache_reset.clearCachedBuild();
