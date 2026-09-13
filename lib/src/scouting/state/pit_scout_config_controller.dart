import '../services/scout_config_service.dart';
import 'form_config_controller.dart';

class PitScoutConfigController extends FormConfigController {
  PitScoutConfigController({ScoutConfigService? service, super.syncService})
    : super(service: service ?? ScoutConfigService.pit(), label: 'pit');
}
