import 'android_update_service.dart';

Future<void> runAndroidStartupUpdateCheck({
  AndroidUpdateService? service,
}) async {
  final svc = service ?? AndroidUpdateService();
  try {
    if (!await svc.dueForStartupCheck()) return;
    await svc.checkForUpdate();
  } catch (_) {
    // Intentionally empty.
  }
}
