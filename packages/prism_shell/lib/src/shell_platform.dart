import 'package:flutter/foundation.dart';

bool defaultMobilePlatformPredicate(TargetPlatform platform) {
  return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
}
