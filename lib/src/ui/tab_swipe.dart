library;

import 'package:flutter/widgets.dart';

import 'platform_target.dart';

ScrollPhysics? get tabSwipePhysics =>
    isDesktopOs ? const NeverScrollableScrollPhysics() : null;
