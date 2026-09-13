import '../services/scout_config_service.dart';
import 'form_config_controller.dart';

class PrescoutConfigController extends FormConfigController {
  PrescoutConfigController({ScoutConfigService? service, super.syncService})
    : super(
        service: service ?? ScoutConfigService.prescout(),
        label: 'pre-scouting',
      );
}
