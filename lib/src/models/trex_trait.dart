library;

enum TrexTrait {
  autonomous('autonomous', 'Autonomous', _autonomousInstructions),
  defense('defense', 'Defense', _defenseInstructions),
  driverSkill('driverSkill', 'Driver skill', _driverSkillInstructions),
  fuelScoring('fuelScoring', 'Fuel scoring', _fuelScoringInstructions),
  passingPushingStealing(
    'passingPushingStealing',
    'Passing/pushing/stealing',
    _passingPushingStealingInstructions,
  );

  const TrexTrait(this.key, this.label, this.instructions);

  final String key;

  final String label;

  final String instructions;

  static TrexTrait? byKey(String? key) {
    for (final trait in TrexTrait.values) {
      if (trait.key == key) return trait;
    }
    return null;
  }
}

const _autonomousInstructions =
    'Failures + fixes\n'
    'Do they interrupt alliance partner autos?\n\n'
    'Things that are helpful to report:\n'
    '- Starting position\n'
    '- Which source(s) do they go to: Neutral Zone? Outpost? Depot?\n'
    '- Do they cross the bump, cross the trench, or both?\n'
    '- How many times did they intake fuel?\n'
    '- Did they push a lot of fuel while intaking, more than they intook?\n\n'
    'Example: fast autonomous -> depot bump -> goes over the bump and under '
    'the trench -> intakes fuel twice in auto -> fast scoring -> accurate.';

const _defenseInstructions =
    'Failures + fixes\n'
    'Location: where do they play defense from?\n'
    'Effectiveness: are they preventing other teams from scoring or intaking?\n'
    'Fouls: do they isolate major elements of the field (blocking bumps from '
    'the neutral zone)? Do they contact robots in the neutral zone? Do they '
    "touch the opponent's tower in the last 30 seconds of the match?\n"
    'Pin fouls: do they pin robots for too long (more than 3 seconds)?\n'
    'Drivetrain vs. drivetrain: do they get pushed around easily?\n'
    'Counterspin: how good are they at spinning into and out of defense or '
    'pins?\n'
    'How often do they play defense?';

const _driverSkillInstructions =
    'Fouls: do they contact opponent towers in the last 30 seconds of the '
    'match, or opponents in the neutral zone?\n'
    'Decision making: how quickly do they make path/route decisions? Do '
    'they shift gears effectively when something bad happens?\n'
    'Alliance: do they run into their alliance partners?\n'
    'Countering defense: how effective is defense against them?\n'
    'Alignment timing: how long does it take them to score lined up with '
    'the scoring zone?\n'
    'Cycles: are they cycling fuel as efficiently as possible?\n'
    'Can they shoot while on the move?';

const _fuelScoringInstructions =
    'Failures + fixes\n'
    'Cycle timing: how fast do they cycle fuel?\n'
    'Launcher description: double or more? Turret? Other?\n'
    'Stealing/scavenging fuel from the opposite side?\n'
    'Human player skill (not super important): does the human player avoid '
    'throwing fuel above the alliance wall?\n'
    'Fouls: do they intentionally launch fuel out of the field? Do they '
    'score outside of their alliance zone?';

const _passingPushingStealingInstructions =
    'Failures + fixes\n'
    'Passing fuel: how fast do they pass fuel into their alliance zone? How '
    "often do they pass fuel? Is their passing benefiting the alliance's "
    'score?\n'
    'Pushing fuel: how good are they at pushing fuel around? How often are '
    'they pushing? Can they push fuel from near the hub all the way into '
    'the alliance zone?\n'
    'Are they primarily pushing and/or passing because of strategy, or '
    'because of an issue (a mechanism broke)?';
