library;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

bool get isDesktopPlatform => !kIsWeb && isDesktopOs;

bool get isDesktopOs =>
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.linux;

bool get isMacosPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

bool get isAndroidPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get isApplePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

bool get isLocalModelPlatform => isDesktopPlatform || isApplePlatform;
