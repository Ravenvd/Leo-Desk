import 'package:flutter/foundation.dart';

/// Fires whenever a background sync or a database pull completes, so
/// open screens can reload their data. The value is just a counter —
/// listeners only care that it changed.
final ValueNotifier<int> syncCompleted = ValueNotifier<int>(0);

void notifySyncCompleted() {
  syncCompleted.value++;
}
