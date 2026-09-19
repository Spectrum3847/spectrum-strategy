library;

import '../../ui/platform_target.dart';
import 'apple_assistant_backend.dart';
import 'assistant_backend.dart';
import 'assistant_tool.dart';
import 'local_assistant_backend.dart';

List<AssistantBackend> localAssistantBackends(AssistantToolRegistry? tools) =>
    <AssistantBackend>[
      if (isDesktopPlatform) LocalAssistantBackend(tools: tools),
      if (isApplePlatform) AppleAssistantBackend(tools: tools),
    ];
