import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/models/trex_trait_report.dart';
import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/services/team_lookup_notes.dart';

void main() {
  const drivetrainField = ScoutConfigField(
    title: 'Drivetrain',
    type: ScoutFieldType.text,
    code: 'drivetrain',
  );

  test('an entry-level note carries its match and author', () {
    final notes = TeamLookupNotes.notesForTeam(
      teamNumber: 3847,
      scoutEntries: [
        ScoutEntry(
          matchId: 'qm12',
          teamNumber: 3847,
          notes: 'tipped over reaching for the bar',
          authorDisplayName: 'scouter one',
        ),
      ],
    );

    expect(notes, hasLength(1));
    expect(notes.single.heading, contains('qm12'));
    expect(notes.single.heading, contains('scouter one'));
    expect(notes.single.text, 'tipped over reaching for the bar');
  });

  test('a team with no scouting entries has no scouting notes', () {
    final notes = TeamLookupNotes.notesForTeam(
      teamNumber: 3847,
      scoutEntries: [ScoutEntry(matchId: 'qm1', teamNumber: 254)],
    );

    expect(notes, isEmpty);
  });

  test('a pit answer is labelled by its field title', () {
    final notes = TeamLookupNotes.notesForTeam(
      teamNumber: 3847,
      scoutEntries: const [],
      pitEntry: PitScoutEntry(
        teamNumber: 3847,
        fieldValues: const {'drivetrain': 'Swerve'},
      ),
      pitConfig: const ScoutConfig(
        title: 'Pit',
        sections: [
          ScoutConfigSection(name: 'Robot', fields: [drivetrainField]),
        ],
      ),
    );

    expect(notes, hasLength(1));
    expect(notes.single.heading, 'Pit scouting: Drivetrain');
    expect(notes.single.text, 'Swerve');
  });

  test('a pit answer with no config is dropped rather than guessed', () {
    final notes = TeamLookupNotes.notesForTeam(
      teamNumber: 3847,
      scoutEntries: const [],
      pitEntry: PitScoutEntry(
        teamNumber: 3847,
        fieldValues: const {'drivetrain': 'Swerve'},
      ),
    );

    expect(notes, isEmpty);
  });

  test('a T-Rex report is labelled by its trait and filtered to this team', () {
    final notes = TeamLookupNotes.notesForTeam(
      teamNumber: 3847,
      scoutEntries: const [],
      trexReports: [
        TrexTraitReport(
          trait: 'defense',
          teamNumber: 3847,
          matchNumber: 12,
          report: 'plays defense from the far side',
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
        TrexTraitReport(
          trait: 'defense',
          teamNumber: 254,
          matchNumber: 12,
          report: 'a different team entirely',
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      ],
    );

    expect(notes, hasLength(1));
    expect(notes.single.heading, 'T-Rex: Defense');
    expect(notes.single.text, 'plays defense from the far side');
  });

  test('an empty T-Rex report is not shown as a blank note', () {
    final notes = TeamLookupNotes.notesForTeam(
      teamNumber: 3847,
      scoutEntries: const [],
      trexReports: [
        TrexTraitReport(
          trait: 'defense',
          teamNumber: 3847,
          matchNumber: 12,
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      ],
    );

    expect(notes, isEmpty);
  });

  test('all three sources appear together, scouting first', () {
    final notes = TeamLookupNotes.notesForTeam(
      teamNumber: 3847,
      scoutEntries: [
        ScoutEntry(
          matchId: 'qm1',
          teamNumber: 3847,
          notes: 'fast auto',
          authorDisplayName: 'a',
        ),
      ],
      pitEntry: PitScoutEntry(
        teamNumber: 3847,
        fieldValues: const {'drivetrain': 'Swerve'},
      ),
      pitConfig: const ScoutConfig(
        title: 'Pit',
        sections: [
          ScoutConfigSection(name: 'Robot', fields: [drivetrainField]),
        ],
      ),
      trexReports: [
        TrexTraitReport(
          trait: 'defense',
          teamNumber: 3847,
          matchNumber: 12,
          report: 'good defense',
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      ],
    );

    expect(notes, hasLength(3));
    expect(notes[0].text, 'fast auto');
    expect(notes[1].text, 'Swerve');
    expect(notes[2].text, 'good defense');
  });
}
