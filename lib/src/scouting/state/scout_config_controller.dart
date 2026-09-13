import '../services/scout_config_service.dart';
import 'form_config_controller.dart';

class ScoutConfigController extends FormConfigController {
  ScoutConfigController({ScoutConfigService? service, super.syncService})
    : super(service: service ?? ScoutConfigService(), label: 'match');
}
