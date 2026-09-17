import 'desktop_self_update_service.dart';
import 'desktop_update_service.dart';

Future<void> runDesktopStartupUpdateCheck({
  DesktopUpdateService? updateService,
  DesktopSelfUpdateService? selfUpdate,
}) async {
  final self = selfUpdate ?? DesktopSelfUpdateService();
  if (!self.canSelfUpdate) return;
  final service = updateService ?? DesktopUpdateService();
  try {
    if (!(await service.autoUpdateEnabled())) return;
    final channel = await service.currentChannel();
    final result = await service.checkForUpdate(channel: channel);
    final update = result.update;
    final assetUrl = update?.assetUrl;
    final digest = update?.expectedSha256;
    if (assetUrl == null || digest == null || digest.isEmpty) return;
    await self.update(Uri.parse(assetUrl), expectedSha256: digest);
  } catch (_) {
    // Intentionally empty.
  }
}
