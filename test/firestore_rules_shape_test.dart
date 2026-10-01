import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/services/strategy_board_sync_service.dart';

void main() {
  final rules = File('firestore.rules').readAsStringSync();

  String braceBounded(String source, int from) {
    final start = source.indexOf('{', from);
    if (start == -1) {
      fail('no opening brace found from offset $from');
    }
    var depth = 0;
    String? quote;
    for (var i = start; i < source.length; i++) {
      final ch = source[i];
      if (quote != null) {
        if (ch == r'\') {
          i++;
        } else if (ch == quote) {
          quote = null;
        }
        continue;
      }
      if (ch == "'" || ch == '"') {
        quote = ch;
        continue;
      }
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) return source.substring(start, i + 1);
      }
    }
    fail('unbalanced braces from offset $from');
  }

  Set<String> whitelistOf(String function) {
    final sigStart = rules.indexOf('function $function(');
    expect(sigStart, isNot(-1), reason: '$function is not in firestore.rules');
    final body = braceBounded(rules, sigStart);
    final match = RegExp(r'hasOnly\(\[([^\]]*)\]\)').firstMatch(body);
    expect(
      match,
      isNotNull,
      reason: '$function has no hasOnly whitelist of its own',
    );
    return RegExp(r"'([^']+)'")
        .allMatches(match!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();
  }

  Set<String> rulesFunctionNames() =>
      RegExp(r'function (\w+)\(')
          .allMatches(rules)
          .map((m) => m.group(1)!)
          .toSet();

  bool isDocumentShapeFunction(String function) {
    final sigStart = rules.indexOf('function $function(');
    if (sigStart == -1) return false;
    final body = braceBounded(rules, sigStart);
    return RegExp(r'(?:data|block)\.keys\(\)\.hasOnly\(').hasMatch(body);
  }

  String stripComments(String source) {
    final out = StringBuffer();
    String? quote;
    var i = 0;
    while (i < source.length) {
      final ch = source[i];
      if (quote != null) {
        out.write(ch);
        if (ch == r'\' && i + 1 < source.length) {
          out.write(source[i + 1]);
          i += 2;
          continue;
        }
        if (ch == quote) quote = null;
        i++;
        continue;
      }
      if (ch == "'" || ch == '"') {
        quote = ch;
        out.write(ch);
        i++;
        continue;
      }
      if (ch == '/' && i + 1 < source.length && source[i + 1] == '/') {
        while (i < source.length && source[i] != '\n') {
          i++;
        }
        continue;
      }
      if (ch == '/' && i + 1 < source.length && source[i + 1] == '*') {
        i += 2;
        while (i + 1 < source.length &&
            !(source[i] == '*' && source[i + 1] == '/')) {
          out.write(source[i] == '\n' ? '\n' : ' ');
          i++;
        }
        i += 2;
        continue;
      }
      out.write(ch);
      i++;
    }
    return out.toString();
  }

  String dartSource(String path) =>
      stripComments(File(path).readAsStringSync());

  String functionBody(String source, String function, {String? className}) {
    var scope = source;
    var offset = 0;
    if (className != null) {
      final classMatch = RegExp(r'class\s+' + RegExp.escape(className) + r'\b')
          .firstMatch(source);
      expect(classMatch, isNotNull, reason: 'class $className not found');
      offset = classMatch!.end;
      scope = braceBounded(source, offset);
    }

    final sig = RegExp(
      r'\b' + RegExp.escape(function) + r'\s*\([^;]*?\)\s*(?:async\s*)?(\{|=>)',
    );
    final match = sig.firstMatch(scope);
    expect(
      match,
      isNotNull,
      reason: className == null
          ? 'function $function not found'
          : 'function $function not found in class $className',
    );
    final m = match!;
    if (m.group(1) == '{') {
      return braceBounded(scope, m.end - 1);
    }

    var p = m.end;
    while (p < scope.length && scope[p] == ' ') {
      p++;
    }
    if (p < scope.length && scope[p] == '<') {
      var angle = 1;
      p++;
      while (p < scope.length && angle > 0) {
        if (scope[p] == '<') angle++;
        if (scope[p] == '>') angle--;
        p++;
      }
      while (p < scope.length && scope[p] == ' ') {
        p++;
      }
    }
    if (p >= scope.length || scope[p] != '{') {
      fail(
        'function $function is expression-bodied (=>) but its value is '
        'not a map literal directly -- extend functionBody to follow '
        'whatever it delegates to instead of guessing at a nearby brace.',
      );
    }
    return braceBounded(scope, p);
  }

  bool isIdentifierChar(String ch) => RegExp(r'[A-Za-z0-9_.]').hasMatch(ch);

  Set<String> addedKeys(String body) {
    final keys = <String>{};
    final unrecognized = <String>{};
    final stack = <String>[];
    String? quote;
    var i = 0;
    while (i < body.length) {
      final ch = body[i];
      if (quote != null) {
        if (ch == r'\' && i + 1 < body.length) {
          i += 2;
          continue;
        }
        if (ch == quote) quote = null;
        i++;
        continue;
      }
      if (ch == "'" || ch == '"') {
        final end = body.indexOf(ch, i + 1);
        if (end != -1) {
          var j = end + 1;
          while (j < body.length && body[j] == ' ') {
            j++;
          }

          var k = i - 1;
          while (k >= 0 && (body[k] == ' ' || body[k] == '\n')) {
            k--;
          }
          final precededByEntryStart = k < 0 || '{,[)'.contains(body[k]);
          if (j < body.length &&
              body[j] == ':' &&
              precededByEntryStart &&
              stack.isNotEmpty &&
              stack.last == '{') {
            keys.add(body.substring(i + 1, end));
          }
        }
        quote = ch;
        i++;
        continue;
      }
      if (ch == ':' && stack.isNotEmpty && stack.last == '{') {
        var k = i - 1;
        while (k >= 0 && body[k] == ' ') {
          k--;
        }
        final tokenEnd = k + 1;
        var tokenStart = k;
        while (tokenStart >= 0 && isIdentifierChar(body[tokenStart])) {
          tokenStart--;
        }
        tokenStart++;
        if (tokenStart <= k) {
          var before = tokenStart - 1;
          while (before >= 0 && (body[before] == ' ' || body[before] == '\n')) {
            before--;
          }
          final precededByEntryStart =
              before < 0 || '{,['.contains(body[before]);
          if (precededByEntryStart) {
            unrecognized.add(body.substring(tokenStart, tokenEnd));
          }
        }
      }
      if (ch == '{' || ch == '[' || ch == '(') {
        stack.add(ch);
        i++;
        continue;
      }
      if (ch == '}' || ch == ']' || ch == ')') {
        if (stack.isNotEmpty) stack.removeLast();
        i++;
        continue;
      }
      i++;
    }
    if (unrecognized.isNotEmpty) {
      fail(
        'found $unrecognized used as a non-literal map key -- this '
        'extractor only reads quoted string-literal keys, so a key written '
        'any other way is invisible to it. Either give it a quoted key or '
        'teach addedKeys to read this shape; do not leave it unaccounted '
        'for.',
      );
    }
    keys.addAll(
      RegExp(r"""\[\s*(['"])([^'"]+)\1\s*\]\s*=(?!=)""")
          .allMatches(body)
          .map((m) => m.group(2)!),
    );
    return keys;
  }

  Set<String> removedKeys(String body) =>
      RegExp(r"""\.remove\(\s*(['"])([^'"]+)\1\s*\)""")
          .allMatches(body)
          .map((m) => m.group(2)!)
          .toSet();

  Set<String> keysFrom(List<String> bodies) {
    final keys = <String>{};
    for (final body in bodies) {
      keys.addAll(addedKeys(body));
    }
    for (final body in bodies) {
      keys.removeAll(removedKeys(body));
    }
    return keys;
  }

  test('a scout entry with every field set fits isValidScoutEntry', () {
    final entry = ScoutEntry(
      matchId: 'qm1',
      teamNumber: 3847,
      alliance: 'Blue',
      notes: 'notes',
      authorUid: 'uid',
      authorDisplayName: 'Scouter',
      createdAt: DateTime.utc(2026, 4, 20, 14, 30),
      updatedAt: DateTime.utc(2026, 4, 20, 16),
      fieldValues: const {'auto_l1': 2},
      tbaMatchKey: '2026cc_qm1',
      strokesByPhase: {'auton': <Object>[]},
      addedManually: true,
    );

    final sent = {...entry.toJson().keys, 'updatedAtTs'};

    expect(sent, everyElement(isIn(whitelistOf('isValidScoutEntry'))));
  });

  test('a strategy board drawn for an event fits isValidStrategyBoard', () {
    final session = StrategySession.create(eventKey: '2026cc')
      ..selectedRobotTeam = 3847;
    final sent = prepareBoardPayload(session, 'uid', 'Lead', 'ts').keys;

    expect(sent, everyElement(isIn(whitelistOf('isValidStrategyBoard'))));
  });

  final scoutEntry = dartSource('lib/src/scouting/models/scout_entry.dart');
  final scoutingSync = dartSource(
    'lib/src/scouting/services/scouting_sync_service.dart',
  );
  final strategySession = dartSource('lib/src/models/strategy_session.dart');
  final strategyBoardSync = dartSource(
    'lib/src/services/strategy_board_sync_service.dart',
  );
  final pitScoutEntry = dartSource(
    'lib/src/scouting/models/pit_scout_entry.dart',
  );
  final pitScoutingSync = dartSource(
    'lib/src/scouting/services/pit_scouting_sync_service.dart',
  );
  final prescoutEntry = dartSource(
    'lib/src/scouting/models/prescout_entry.dart',
  );
  final prescoutingSync = dartSource(
    'lib/src/scouting/services/prescouting_sync_service.dart',
  );
  final trexTraitReport = dartSource('lib/src/models/trex_trait_report.dart');
  final trexTraitReportSync = dartSource(
    'lib/src/services/trex_trait_report_sync_service.dart',
  );
  final postMatchReport = dartSource('lib/src/models/post_match_report.dart');
  final postMatchReportSync = dartSource(
    'lib/src/services/post_match_report_sync_service.dart',
  );
  final scoutShiftSchedule = dartSource(
    'lib/src/scouting/models/scout_shift_schedule.dart',
  );
  final scoutShiftSync = dartSource(
    'lib/src/scouting/services/scout_shift_sync_service.dart',
  );
  final shiftTrade = dartSource('lib/src/scouting/models/shift_trade.dart');
  final shiftTradeSync = dartSource(
    'lib/src/scouting/services/shift_trade_sync_service.dart',
  );
  final bugReportService = dartSource(
    'lib/src/services/issue_report_service.dart',
  );
  final telemetryService = dartSource(
    'lib/src/services/telemetry_service.dart',
  );
  final assistantBackend = dartSource(
    'lib/src/services/assistant/assistant_backend.dart',
  );
  final assistantSummaryCache = dartSource(
    'lib/src/services/assistant/firestore_remote_assistant_cache.dart',
  );
  final assistantRequestModel = dartSource(
    'lib/src/services/assistant/assistant_requests.dart',
  );
  final assistantRequestSync = dartSource(
    'lib/src/services/assistant/firestore_assistant_requests.dart',
  );
  final assistantChatSession = dartSource(
    'lib/src/models/assistant_chat_session.dart',
  );
  final remoteChatStore = dartSource('lib/src/services/remote_chat_store.dart');
  final userRoleService = dartSource('lib/src/services/user_role_service.dart');

  final guarded = <String, Set<String> Function()>{
    'isValidScoutEntry': () => keysFrom([
      functionBody(scoutEntry, 'toJson', className: 'ScoutEntry'),
      functionBody(scoutingSync, 'push'),
    ]),
    'isValidStrategyBoard': () => keysFrom([
      functionBody(strategySession, 'toJson', className: 'StrategySession'),
      functionBody(strategyBoardSync, 'prepareBoardPayload'),
    ]),
    'isValidPitScoutEntry': () => keysFrom([
      functionBody(pitScoutEntry, 'toJson', className: 'PitScoutEntry'),
      functionBody(pitScoutEntry, 'toRemoteJson', className: 'PitScoutEntry'),
      functionBody(pitScoutingSync, 'push'),
    ]),
    'isValidPrescoutEntry': () => keysFrom([
      functionBody(prescoutEntry, 'toJson', className: 'PrescoutEntry'),
      functionBody(prescoutingSync, 'push'),
    ]),
    'isValidTrexTraitReport': () => keysFrom([
      functionBody(trexTraitReport, 'toJson', className: 'TrexTraitReport'),
      functionBody(trexTraitReportSync, 'push'),
    ]),
    'isValidPostMatchReport': () => keysFrom([
      functionBody(postMatchReport, 'toJson', className: 'PostMatchReport'),
      functionBody(postMatchReportSync, 'push'),
    ]),
    'isValidScoutShiftSchedule': () => keysFrom([
      functionBody(
        scoutShiftSchedule,
        'toJson',
        className: 'ScoutShiftSchedule',
      ),
      functionBody(scoutShiftSync, 'push'),
    ]),
    'isValidShiftTrade': () => keysFrom([
      functionBody(shiftTrade, 'toJson', className: 'ShiftTrade'),
      functionBody(shiftTradeSync, 'create'),
    ]),
    'isValidShiftBlock': () => keysFrom([
      functionBody(scoutShiftSchedule, 'toJson', className: 'ScoutShiftBlock'),
    ]),
    'isValidBugReport': () =>
        keysFrom([functionBody(bugReportService, 'submit')]),
    'isValidTelemetry': () =>
        keysFrom([functionBody(telemetryService, 'logEvent')]),
    'isValidAssistantSummary': () => keysFrom([
      functionBody(assistantBackend, 'toJson', className: 'AssistantSummary'),
      functionBody(assistantSummaryCache, 'write'),
    ]),
    'isValidAssistantRequest': () => keysFrom([
      functionBody(
        assistantRequestModel,
        'toJson',
        className: 'PendingAssistantRequest',
      ),
      functionBody(assistantRequestSync, 'post'),
      functionBody(assistantRequestSync, 'claim'),
    ]),
    'isValidAssistantChat': () => keysFrom([
      functionBody(
        assistantChatSession,
        'toJson',
        className: 'AssistantChatSession',
      ),
      functionBody(remoteChatStore, 'write'),
    ]),
    'isValidNewProfile': () =>
        keysFrom([functionBody(userRoleService, 'fetchOrCreateProfile')]),
    'isValidAdminProfileCreate': () =>
        keysFrom([functionBody(userRoleService, 'updateRoles')]),
  };

  const exemptions = <String, Map<String, String>>{};

  const nestedValueKeys = <String, Map<String, String>>{
    'isValidAssistantChat': {
      'role':
          'AssistantChatSession.toJson()\'s turns list holds one '
          '{role, content} map per turn; those are fields of each turn, '
          'not top-level document keys.',
      'content': 'Same turns entry as role, above.',
    },
  };

  for (final entry in guarded.entries) {
    test('the Dart payload for ${entry.key} fits its own rules whitelist', () {
      final nested = nestedValueKeys[entry.key] ?? const <String, String>{};
      final sent = entry.value().difference(nested.keys.toSet());
      final allowed = whitelistOf(entry.key);
      expect(
        sent,
        isNotEmpty,
        reason:
            'no keys were extracted for ${entry.key} at all -- that is what '
            'a broken extractor looks like, not a model with nothing to '
            'send, so this needs fixing rather than skipping.',
      );
      expect(
        sent,
        everyElement(isIn(allowed)),
        reason:
            'a key the Dart side can send is missing from ${entry.key} in '
            'firestore.rules -- that key gets every write rejected by the '
            'server the way scoutEntries.createdAt did.',
      );
      final exempt = exemptions[entry.key] ?? const <String, String>{};
      final unaccounted = allowed
          .difference(sent)
          .difference(exempt.keys.toSet());
      expect(
        unaccounted,
        isEmpty,
        reason:
            '${entry.key} allows $unaccounted but nothing in the Dart '
            'extraction for it produces those keys and no exemption names '
            'them -- either the extractor missed a real key (it broke) or '
            'the key is legitimately server-set/legacy/mcp-only and needs '
            'an entry in the exemptions map above with a one-line reason.',
      );
    });
  }

  const unguarded = <String, String>{
    'isValidTraitTable':
        'The Traits destination was removed from the app; the app-side '
        'controller, sync service and model followed it out (AGENTS.md '
        'glossary). Only spectrum-mcp writes traitTables now.',
    'isValidPickList':
        'Pick lists were removed from the app SURFACE, not from the code: '
        'PickListController is still constructed in main.dart with a live '
        'FirestorePickListSyncService, and create/addTeam/removeTeam/'
        'rename/reorder/delete all still call into it and would still '
        'write pickLists today. The write path is dead only because no UI '
        'screen calls any of those methods anymore (the pick list tab was '
        'removed) -- spectrum-mcp is the only thing writing this collection '
        'right now, but wiring a button back to one of those methods would '
        'silently re-arm a write path this test does not guard.',
    'isValidScoutAssignment':
        'Scout assignments were removed from the app surface (AGENTS.md '
        'glossary, superseded by the Scouting shifts grid); '
        'ScoutAssignmentController and its sync service are not constructed '
        'anywhere in main.dart, so nothing on the Dart side can reach the '
        'write path. spectrum-mcp still reads and writes scoutAssignments '
        'directly.',
  };

  test(
    'every document-shape rules whitelist is guarded or explicitly unguarded',
    () {
      final documentShapeFunctions = rulesFunctionNames()
          .where(isDocumentShapeFunction)
          .toSet();
      final covered = {...guarded.keys, ...unguarded.keys};
      expect(
        covered,
        equals(documentShapeFunctions),
        reason:
            'a new hasOnly([...]) document-shape whitelist showed up in '
            'firestore.rules with no matching guard or unguarded entry in '
            'this test -- add one or the other so the set stays closed.',
      );
    },
  );
}
