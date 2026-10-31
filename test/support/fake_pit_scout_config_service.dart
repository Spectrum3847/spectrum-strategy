import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/services/scout_config_service.dart';

class FakePitScoutConfigService extends ScoutConfigService {
  FakePitScoutConfigService() : super.pit();

  ScoutConfig? _config;

  @override
  Future<ScoutConfig?> loadStored() async => _config;

  @override
  Future<void> save(ScoutConfig config) async {
    _config = config;
  }
}
