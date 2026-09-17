import 'dart:convert';

import 'package:apple_ai/apple_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/services/assistant/apple_assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_tool.dart';
import 'package:spectrumstrategy/src/services/assistant/mcp_tool_provider.dart';
import 'package:spectrumstrategy/src/services/mcp/mcp_oauth_service.dart';

const _baseUrl = 'https://spectrum-mcp-strategy.spectrum-3847.workers.dev';

final List<Map<String, dynamic>> _liveMcpTools = <Map<String, dynamic>>[
  _tool(
    'whoami',
    'The account this server is acting as, and the roles it holds. Call '
        'this first when a permission question comes up: the roles decide '
        'what every other tool can do.',
    <String, dynamic>{
      'type': 'object',
      'properties': {},
      'additionalProperties': false,
    },
    scope: 'spectrum:read',
  ),
  _tool(
    'list_collections',
    'Every collection this server exposes, what it holds, and whether it '
        'can be written.',
    <String, dynamic>{
      'type': 'object',
      'properties': {},
      'additionalProperties': false,
    },
    scope: 'spectrum:read',
  ),
  _tool('get_document', 'One document by collection and id.', <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'collection': _collectionArg,
      'id': <String, dynamic>{'type': 'string'},
    },
    'required': <String>['collection', 'id'],
    'additionalProperties': false,
  }, scope: 'spectrum:read'),
  _tool(
    'query_collection',
    'Documents from one collection, optionally filtered and ordered. '
        'Filters are field/operator/value triples combined with AND, '
        'matching Firestore query semantics.',
    <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'collection': _collectionArg,
        'filters': <String, dynamic>{
          'type': 'array',
          'description': 'AND-combined field filters.',
          'items': <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'field': <String, dynamic>{'type': 'string'},
              'op': <String, dynamic>{
                'type': 'string',
                'enum': <String>[
                  '==',
                  '!=',
                  '<',
                  '<=',
                  '>',
                  '>=',
                  'array-contains',
                  'in',
                ],
              },
              'value': <String, dynamic>{
                'description':
                    'String, number, boolean, or array for the "in" '
                    'operator.',
              },
            },
            'required': <String>['field', 'op', 'value'],
            'additionalProperties': false,
          },
        },
        'orderBy': <String, dynamic>{
          'type': 'string',
          'description': 'Field to sort on.',
        },
        'descending': <String, dynamic>{'type': 'boolean'},
        'limit': <String, dynamic>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 200,
          'default': 50,
        },
      },
      'required': <String>['collection'],
      'additionalProperties': false,
    },
    scope: 'spectrum:read',
  ),
  _tool(
    'create_document',
    'Add a document to a writable collection. Most collections require '
        'authorUid to equal your own uid; call whoami for it. Read an '
        'existing document first to match the field shape.',
    <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'collection': _collectionArg,
        'id': <String, dynamic>{
          'type': 'string',
          'description': 'Document id. Omit to generate a uuid.',
        },
        'data': <String, dynamic>{
          'type': 'object',
          'description': 'Full document body as plain JSON.',
        },
      },
      'required': <String>['collection', 'data'],
      'additionalProperties': false,
    },
    scope: 'spectrum:write',
    readOnly: false,
  ),
  _tool(
    'update_document',
    'Change named fields on an existing document. Only the fields you send '
        'are touched. Rules keep authorUid immutable and require updatedAt '
        'to move forward.',
    <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'collection': _collectionArg,
        'id': <String, dynamic>{'type': 'string'},
        'data': <String, dynamic>{
          'type': 'object',
          'description': 'The fields to change, as plain JSON.',
        },
      },
      'required': <String>['collection', 'id', 'data'],
      'additionalProperties': false,
    },
    scope: 'spectrum:write',
    readOnly: false,
  ),
  _tool(
    'delete_document',
    'Remove a document. Not reversible; confirm with the user first.',
    <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'collection': _collectionArg,
        'id': <String, dynamic>{'type': 'string'},
      },
      'required': <String>['collection', 'id'],
      'additionalProperties': false,
    },
    scope: 'spectrum:write',
    readOnly: false,
  ),
  _tool(
    'get_team_epa',
    "A team's Statbotics EPA (expected points added) and win/loss record: "
        'the current season by default, or one specific year. Prefer this '
        'over the Firestore collection tools for a calculated strength '
        "number; use scoutEntries/pickLists for this team's own in-person "
        'observations.',
    <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'team': <String, dynamic>{
          'type': 'integer',
          'minimum': 1,
          'description': 'FRC team number, e.g. 3847.',
        },
        'year': <String, dynamic>{
          'type': 'integer',
          'minimum': 1992,
          'maximum': 2100,
          'description': "Season year. Omit for the team's current EPA.",
        },
      },
      'required': <String>['team'],
      'additionalProperties': false,
    },
    scope: 'spectrum:read',
  ),
  _tool(
    'get_event_teams',
    'Every team at an event with its Statbotics EPA and event record, for '
        'ranking the team list at that event. Prefer this over the '
        'Firestore collection tools for the official field of teams; use '
        "scoutEntries/pickLists for this team's own rankings and notes.",
    <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'eventKey': <String, dynamic>{
          'type': 'string',
          'description': 'TBA event key, e.g. 2026txhou.',
        },
      },
      'required': <String>['eventKey'],
      'additionalProperties': false,
    },
    scope: 'spectrum:read',
  ),
  _tool(
    'get_team_events',
    "A team's events for one season with per-event EPA, from Statbotics. "
        'Prefer this over the Firestore collection tools for the official '
        'event/EPA history; use get_team_events_tba instead when only the '
        'schedule dates are needed, not EPA.',
    <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'team': <String, dynamic>{
          'type': 'integer',
          'minimum': 1,
          'description': 'FRC team number, e.g. 3847.',
        },
        'year': <String, dynamic>{
          'type': 'integer',
          'minimum': 1992,
          'maximum': 2100,
          'description': 'Season year.',
        },
      },
      'required': <String>['team', 'year'],
      'additionalProperties': false,
    },
    scope: 'spectrum:read',
  ),
  _tool(
    'get_event_matches',
    'The Blue Alliance match schedule and results for an event, optionally '
        'filtered to qualification or playoff matches. Prefer this over '
        'the Firestore collection tools for the official schedule and '
        'scores; use scoutEntries for what a scout observed during a '
        'match.',
    <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'eventKey': <String, dynamic>{
          'type': 'string',
          'description': 'TBA event key, e.g. 2026txhou.',
        },
        'level': <String, dynamic>{
          'type': 'string',
          'enum': <String>['qual', 'playoff'],
          'description':
              'Restrict to qualification or playoff matches. Omit for '
              'every match.',
        },
      },
      'required': <String>['eventKey'],
      'additionalProperties': false,
    },
    scope: 'spectrum:read',
  ),
  _tool(
    'get_team_events_tba',
    "A team's events for one season from The Blue Alliance: names and "
        'dates, not EPA. Prefer get_team_events instead when EPA is what '
        'is needed.',
    <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'team': <String, dynamic>{
          'type': 'integer',
          'minimum': 1,
          'description': 'FRC team number, e.g. 3847.',
        },
        'year': <String, dynamic>{
          'type': 'integer',
          'minimum': 1992,
          'maximum': 2100,
          'description': 'Season year.',
        },
      },
      'required': <String>['team', 'year'],
      'additionalProperties': false,
    },
    scope: 'spectrum:read',
  ),
  _tool(
    'get_event_rankings',
    'The current ranking table for an event, from The Blue Alliance. '
        'Prefer this over the Firestore collection tools for the official '
        "standings; use pickLists for this team's own alliance-selection "
        'ranking.',
    <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'eventKey': <String, dynamic>{
          'type': 'string',
          'description': 'TBA event key, e.g. 2026txhou.',
        },
      },
      'required': <String>['eventKey'],
      'additionalProperties': false,
    },
    scope: 'spectrum:read',
  ),
  _tool(
    'get_scout_config',
    'The QRScout-compatible JSON for one scout form, by manifest key (see '
        'scoutConfigForms).',
    <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'formKey': <String, dynamic>{'type': 'string'},
      },
      'required': <String>['formKey'],
      'additionalProperties': false,
    },
    scope: 'spectrum:read',
  ),
  _tool(
    'update_scout_config',
    'Replace a scout form config. Applies the same edit rules the app '
        'does: a choice already in play cannot be removed, only retired, '
        'and the revision stamp advances.',
    <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'formKey': <String, dynamic>{'type': 'string'},
        'config': <String, dynamic>{
          'type': 'object',
          'description': 'Full QRScout-compatible config JSON.',
        },
      },
      'required': <String>['formKey', 'config'],
      'additionalProperties': false,
    },
    scope: 'spectrum:write',
    readOnly: false,
  ),
];

const Map<String, dynamic> _collectionArg = <String, dynamic>{
  'type': 'string',
  'description': 'Collection name, from list_collections.',
};

Map<String, dynamic> _tool(
  String name,
  String description,
  Map<String, dynamic> inputSchema, {
  required String scope,
  bool readOnly = true,
}) => <String, dynamic>{
  'name': name,
  'description': description,
  'inputSchema': inputSchema,
  'annotations': <String, dynamic>{'readOnlyHint': readOnly},
  '_meta': <String, dynamic>{'spectrum/scope': scope},
};

http.Response _rpc(int id, Map<String, dynamic> result) => http.Response(
  jsonEncode(<String, dynamic>{'jsonrpc': '2.0', 'id': id, 'result': result}),
  200,
);

McpAssistantToolProvider _connectedMcpProvider() {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'mcp_strategy_oauth_v1': jsonEncode(<String, dynamic>{
      'clientId': 'c1',
      'tokenEndpoint': '$_baseUrl/token',
      'accessToken': 'access-1',
      'refreshToken': 'refresh-1',
      'expiresAt': DateTime.now()
          .add(const Duration(hours: 1))
          .toIso8601String(),
    }),
  });
  final oauth = McpOAuthService(baseUrl: _baseUrl);
  return McpAssistantToolProvider(
    baseUrl: _baseUrl,
    oauth: oauth,
    httpClient: MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'name': 'spectrum-mcp-strategy',
            'mcp_endpoint': '$_baseUrl/mcp',
            'protocol_version': '2026-07-28',
          }),
          200,
        );
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final id = body['id'] as int;
      if (body['method'] == 'initialize') return _rpc(id, <String, dynamic>{});
      if (body['method'] == 'tools/list') {
        return _rpc(id, <String, dynamic>{'tools': _liveMcpTools});
      }
      fail('Unexpected MCP call: ${body['method']}');
    }),
  );
}

int _appleToolChars(List<AppleAiTool> tools) => tools.fold(
  0,
  (sum, tool) =>
      sum +
      tool.name.length +
      tool.description.length +
      jsonEncode(tool.parameters).length,
);

void main() {
  group('AppleAssistantBackend MCP tool cap (#1654)', () {
    test(
      'sends six MCP tools, by the exact names the maintainer decided',
      () async {
        final registry = AssistantToolRegistry([_connectedMcpProvider()]);
        List<AppleAiTool>? sent;
        final backend = AppleAssistantBackend(
          tools: registry,
          availability: () async => const AppleAiAvailability.available(),
          setToolHandler: (_) {},
          respond:
              ({
                required prompt,
                instructions,
                temperature,
                sessionId,
                tools,
              }) async {
                sent = tools;
                return 'Team 3847 climbs in nine of eleven matches this event.';
              },
        );

        await backend.complete(
          const AssistantRequest(
            cacheKey: 'chat',
            prompt: 'who climbs?',
            useTools: true,
          ),
        );

        expect(sent!.map((t) => t.name).toSet(), <String>{
          'mcp_whoami',
          'mcp_get_document',
          'mcp_query_collection',
          'mcp_get_team_epa',
          'mcp_get_event_teams',
          'mcp_get_event_rankings',
        });
      },
    );

    test(
      'the registry keeps every read-only tool, for OpenRouter/llama.cpp',
      () async {
        final registry = AssistantToolRegistry([_connectedMcpProvider()]);

        expect(await registry.tools(), hasLength(11));
      },
    );

    test(
      'the six-tool payload is a fraction of what the full 15 would cost',
      () async {
        final registry = AssistantToolRegistry([_connectedMcpProvider()]);
        List<AppleAiTool>? sentToApple;
        final appleBackend = AppleAssistantBackend(
          tools: registry,
          availability: () async => const AppleAiAvailability.available(),
          setToolHandler: (_) {},
          respond:
              ({
                required prompt,
                instructions,
                temperature,
                sessionId,
                tools,
              }) async {
                sentToApple = tools;
                return 'Team 3847 climbs in nine of eleven matches this event.';
              },
        );
        await appleBackend.complete(
          const AssistantRequest(
            cacheKey: 'chat',
            prompt: 'who climbs?',
            useTools: true,
          ),
        );

        final allSpecs = await registry.tools();
        final uncapped = <AppleAiTool>[
          for (final spec in allSpecs)
            AppleAiTool(
              name: spec.name,
              description: spec.description,
              parameters: spec.parameters,
            ),
        ];

        final beforeChars = _appleToolChars(uncapped);
        final afterChars = _appleToolChars(sentToApple!);

        expect(sentToApple, hasLength(6));
        expect(beforeChars, greaterThan(4000));
        expect(afterChars, lessThan(2800));
        expect(afterChars, lessThan((beforeChars * 0.65).round()));
      },
    );

    test(
      'a dropped tool answers that it is unavailable on mobile, not silence',
      () async {
        final registry = AssistantToolRegistry([_connectedMcpProvider()]);
        AppleAiToolHandler? installed;
        final backend = AppleAssistantBackend(
          tools: registry,
          availability: () async => const AppleAiAvailability.available(),
          setToolHandler: (handler) => installed = handler,
          respond: ({
            required prompt,
            instructions,
            temperature,
            sessionId,
            tools,
          }) async => 'Team 3847 climbs in nine of eleven matches.',
        );

        await backend.complete(
          const AssistantRequest(
            cacheKey: 'chat',
            prompt: 'delete the entry for 118',
            useTools: true,
          ),
        );

        final result = await installed!(
          'mcp_delete_document',
          <String, dynamic>{'collection': 'scoutEntries', 'id': '118'},
        );
        expect(result, contains('not available on mobile'));
      },
    );

    test('tells the model a capability is unavailable rather than staying '
        'silent about it', () async {
      final registry = AssistantToolRegistry([_connectedMcpProvider()]);
      String? capturedInstructions;
      final backend = AppleAssistantBackend(
        tools: registry,
        availability: () async => const AppleAiAvailability.available(),
        setToolHandler: (_) {},
        respond:
            ({
              required prompt,
              instructions,
              temperature,
              sessionId,
              tools,
            }) async {
              capturedInstructions = instructions;
              return 'Team 3847 climbs in nine of eleven matches.';
            },
      );

      await backend.complete(
        const AssistantRequest(
          cacheKey: 'chat',
          prompt: 'delete the entry for 118',
          system: 'Answer for a strategy lead.',
          useTools: true,
        ),
      );

      expect(capturedInstructions, contains('Answer for a strategy lead.'));
      expect(capturedInstructions, contains('not available on mobile'));
    });

    test(
      'no MCP connection means nothing was dropped, so no note is added',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final oauth = McpOAuthService(baseUrl: _baseUrl);
        final registry = AssistantToolRegistry([
          McpAssistantToolProvider(baseUrl: _baseUrl, oauth: oauth),
        ]);
        String? capturedInstructions;
        final backend = AppleAssistantBackend(
          tools: registry,
          availability: () async => const AppleAiAvailability.available(),
          setToolHandler: (_) {},
          respond:
              ({
                required prompt,
                instructions,
                temperature,
                sessionId,
                tools,
              }) async {
                capturedInstructions = instructions;
                return 'Team 3847 climbs in nine of eleven matches.';
              },
        );

        await backend.complete(
          const AssistantRequest(
            cacheKey: 'chat',
            prompt: 'who climbs?',
            system: 'Answer for a strategy lead.',
            useTools: true,
          ),
        );

        expect(capturedInstructions, 'Answer for a strategy lead.');
      },
    );
  });
}
