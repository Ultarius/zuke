import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

void main() {
  group('MetadataBlock.resolveAt', () {
    // The mapping from a reconstructed-YAML position back to the file. Exercised
    // directly because it is the one place the column arithmetic lives, and
    // because the position it returns is what every reference finding depends on.
    const source = SourceLocation(file: 'specs/features/x.feature', line: 10);
    const lines = [
      MetadataLine(content: 'id: FEAT-X', fileLine: 11, contentColumn: 3),
      MetadataLine(content: 'targets:', fileLine: 12, contentColumn: 3),
      MetadataLine(content: '  - backend', fileLine: 13, contentColumn: 3),
    ];
    const block = MetadataBlock(
      content: 'id: FEAT-X\ntargets:\n  - backend\n',
      source: source,
      lines: lines,
    );

    test('maps a content line to the file line it came from', () {
      expect(block.resolveAt(1, 0)?.line, 11);
      expect(block.resolveAt(3, 0)?.line, 13);
    });

    test('shifts a YAML column by the width of the stripped prefix', () {
      // `  - backend` begins at file column 3, so YAML column 2 is file column 5.
      // Getting this wrong keeps the line right and the column wrong, which is
      // the kind of error a line-only assertion would never notice.
      expect(block.resolveAt(3, 2)?.column, 5);
      expect(block.resolveAt(1, 0)?.column, 3);
    });

    test('reports the file it was parsed from', () {
      expect(block.resolveAt(1, 0)?.file, 'specs/features/x.feature');
    });

    test('returns null for a position outside the recorded lines', () {
      // Degrades to the caller's coarser fallback rather than throwing, because a
      // location only ever improves a diagnostic.
      expect(block.resolveAt(0, 0), isNull);
      expect(block.resolveAt(4, 0), isNull);
      expect(block.resolveAt(-1, 0), isNull);
    });

    test('a block with no recorded lines resolves nothing', () {
      const empty = MetadataBlock(content: 'id: FEAT-X\n', source: source);
      expect(empty.resolveAt(1, 0), isNull);
    });
  });

  group('Metadata value positions', () {
    late Directory tempDir;
    late File feature;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('zuke_meta_pos_');
      final specs = Directory('${tempDir.path}/specs/features')
        ..createSync(recursive: true);
      feature = File('${specs.path}/positions.feature');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    ParsedFeature parse(List<String> lines) {
      feature.writeAsStringSync('${lines.join('\n')}\n');
      final parsed = GherkinParser().parseFile(
        feature.readAsStringSync(),
        feature.path,
      );
      expect(parsed.errors, isEmpty, reason: parsed.errors.join('\n'));
      expect(parsed.features, hasLength(1));
      return parsed.features.single;
    }

    test('mapping evidence entries retain their type positions', () {
      final parsed = parse([
        '# spec-begin',
        '# schemaVersion: 1',
        '# id: FEAT-EVIDENCE-POS',
        '# requiredEvidence:',
        '#   - type: domain',
        '#   - evidenceType: security',
        '# spec-end',
        '@FEAT-EVIDENCE-POS',
        'Feature: Evidence positions',
      ]);
      expect(
        parsed.metadata
            .locationOf(MetadataField.requiredEvidence, 'domain')
            ?.line,
        5,
      );
      expect(
        parsed.metadata
            .locationOf(MetadataField.requiredEvidence, 'security')
            ?.line,
        6,
      );
    });

    test('a value maps to the line it was written on', () {
      final parsed = parse([
        '# spec-begin',
        '# schemaVersion: 1',
        '# id: FEAT-POS-001',
        '# targets:',
        '#   - backend',
        '#   - frontend',
        '# spec-end',
        '@FEAT-POS-001',
        'Feature: Positions',
        '  # rule-spec-begin',
        '  # id: RULE-POS-ONE',
        '  # rule-spec-end',
        '  @RULE-POS-ONE',
        '  Rule: One',
        '    @SCN-POS-001',
        '    Scenario: Works',
        '      Given a step',
      ]);

      // `backend` is written on line 5 and `frontend` on line 6, so a single
      // offset for the whole block would be right for one and wrong for the
      // other only by accident.
      expect(
        parsed.metadata.locationOf(MetadataField.targets, 'backend')?.line,
        5,
      );
      expect(
        parsed.metadata.locationOf(MetadataField.targets, 'frontend')?.line,
        6,
      );
      expect(
        parsed.metadata.locationOf(MetadataField.id, 'FEAT-POS-001')?.line,
        3,
      );
    });

    test('the same value in two fields keeps both positions', () {
      // A feature that targets `flutter` and a binding that also targets
      // `flutter` declares the same string twice. Keyed by value alone, one of
      // them would be lost and a finding about the other would point at the
      // wrong line - still inside the block, so nothing would look wrong.
      final parsed = parse([
        '# spec-begin',
        '# schemaVersion: 1',
        '# id: FEAT-POS-006',
        '# targets:',
        '#   - flutter',
        '# bindings:',
        '#   required:',
        '#     - id: binding.cart',
        '#       target: flutter',
        '# spec-end',
        '@FEAT-POS-006',
        'Feature: Positions',
        '  # rule-spec-begin',
        '  # id: RULE-POS-SIX',
        '  # rule-spec-end',
        '  @RULE-POS-SIX',
        '  Rule: Six',
        '    @SCN-POS-006',
        '    Scenario: Works',
        '      Given a step',
      ]);

      // The feature declares it on line 5, the binding on line 9.
      expect(
        parsed.metadata.locationOf(MetadataField.targets, 'flutter')?.line,
        5,
      );
      expect(
        parsed.metadata
            .locationOf(MetadataField.bindingTarget, 'flutter')
            ?.line,
        9,
      );
      // A lookup that knows only the value is ambiguous, and says so rather than
      // guessing.
      expect(parsed.metadata.locationOfAny('flutter'), isNull);
    });

    test('each scalar list records under its own field', () {
      // A list of scalars carries no field to read back, so the field has to be
      // named. Filing every scalar list under one field makes a PBI's location
      // unreachable, and a finding about it silently falls back to the block.
      final parsed = parse([
        '# spec-begin',
        '# schemaVersion: 1',
        '# id: FEAT-POS-008',
        '# targets:',
        '#   - flutter',
        '# pbis:',
        '#   - PBI-ONE',
        '# events:',
        '#   - event.alpha',
        '# featureFlags:',
        '#   - flag.beta',
        '# requiredEvidence:',
        '#   - screenshot',
        '# spec-end',
        '@FEAT-POS-008',
        'Feature: Positions',
        '  # rule-spec-begin',
        '  # id: RULE-POS-EIGHT',
        '  # rule-spec-end',
        '  @RULE-POS-EIGHT',
        '  Rule: Eight',
        '    @SCN-POS-008',
        '    Scenario: Works',
        '      Given a step',
      ]);

      expect(
        parsed.metadata.locationOf(MetadataField.targets, 'flutter')?.line,
        5,
      );
      expect(
        parsed.metadata.locationOf(MetadataField.pbis, 'PBI-ONE')?.line,
        7,
      );
      expect(
        parsed.metadata.locationOf(MetadataField.events, 'event.alpha')?.line,
        9,
      );
      expect(
        parsed.metadata
            .locationOf(MetadataField.featureFlags, 'flag.beta')
            ?.line,
        11,
      );
      expect(
        parsed.metadata
            .locationOf(MetadataField.requiredEvidence, 'screenshot')
            ?.line,
        13,
      );
      // And none of them leaked into another field's map.
      expect(
        parsed.metadata.locationOf(MetadataField.targets, 'PBI-ONE'),
        isNull,
      );
    });

    test('a value declared once resolves without naming its field', () {
      final parsed = parse([
        '# spec-begin',
        '# schemaVersion: 1',
        '# id: FEAT-POS-007',
        '# epic: EPIC-ONLY-ONCE',
        '# spec-end',
        '@FEAT-POS-007',
        'Feature: Positions',
        '  # rule-spec-begin',
        '  # id: RULE-POS-SEVEN',
        '  # rule-spec-end',
        '  @RULE-POS-SEVEN',
        '  Rule: Seven',
        '    @SCN-POS-007',
        '    Scenario: Works',
        '      Given a step',
      ]);

      expect(parsed.metadata.locationOfAny('EPIC-ONLY-ONCE')?.line, 4);
    });

    test('a blank comment line inside the block does not shift positions', () {
      // This is the case that rules out a fixed offset. Two `#` lines inside the
      // block are rebuilt as empty YAML lines, so the content is shorter than
      // the region it came from and any constant offset drifts.
      final parsed = parse([
        '# spec-begin',
        '# schemaVersion: 1',
        '# id: FEAT-POS-002',
        '# targets:',
        '#',
        '#   - backend',
        '#',
        '#   - frontend',
        '# spec-end',
        '@FEAT-POS-002',
        'Feature: Positions',
        '  # rule-spec-begin',
        '  # id: RULE-POS-TWO',
        '  # rule-spec-end',
        '  @RULE-POS-TWO',
        '  Rule: Two',
        '    @SCN-POS-002',
        '    Scenario: Works',
        '      Given a step',
      ]);

      expect(
        parsed.metadata.locationOf(MetadataField.targets, 'backend')?.line,
        6,
      );
      expect(
        parsed.metadata.locationOf(MetadataField.targets, 'frontend')?.line,
        8,
      );
      // An offset computed from the block start would say 5 and 7.
      expect(
        parsed.metadata.locationOf(MetadataField.id, 'FEAT-POS-002')?.line,
        3,
      );
    });

    test('a rule block records positions too', () {
      // Rule blocks are extracted by a separate, stricter implementation, so
      // this guards against only the feature path being wired up.
      final parsed = parse([
        '# spec-begin',
        '# schemaVersion: 1',
        '# id: FEAT-POS-003',
        '# spec-end',
        '@FEAT-POS-003',
        'Feature: Positions',
        '  # rule-spec-begin',
        '  # id: RULE-POS-THREE',
        '  # securityProfile: boundary-profile',
        '  # rule-spec-end',
        '  @RULE-POS-THREE',
        '  Rule: Three',
        '    @SCN-POS-003',
        '    Scenario: Works',
        '      Given a step',
      ]);

      expect(
        parsed.rules.single.metadata
            .locationOf(MetadataField.securityProfile, 'boundary-profile')
            ?.line,
        9,
      );
    });

    test('a column points at the value, not the start of the line', () {
      final parsed = parse([
        '# spec-begin',
        '# schemaVersion: 1',
        '# id: FEAT-POS-004',
        '# securityProfile: boundary-profile',
        '# spec-end',
        '@FEAT-POS-004',
        'Feature: Positions',
        '  # rule-spec-begin',
        '  # id: RULE-POS-FOUR',
        '  # rule-spec-end',
        '  @RULE-POS-FOUR',
        '  Rule: Four',
        '    @SCN-POS-004',
        '    Scenario: Works',
        '      Given a step',
      ]);

      // `# securityProfile: boundary-profile` — the value starts after the
      // stripped `# `, so the column reflects the file, not the YAML.
      expect(
        parsed.metadata
            .locationOf(MetadataField.securityProfile, 'boundary-profile')
            ?.column,
        '# securityProfile: boundary-profile'.indexOf('boundary') + 1,
      );
    });

    test('a block with no position information yields no entries', () {
      // Degrades to the block start rather than inventing a line.
      final parsed = parse([
        '# spec-begin',
        '# schemaVersion: 1',
        '# id: FEAT-POS-005',
        '# spec-end',
        '@FEAT-POS-005',
        'Feature: Positions',
        '  # rule-spec-begin',
        '  # id: RULE-POS-FIVE',
        '  # rule-spec-end',
        '  @RULE-POS-FIVE',
        '  Rule: Five',
        '    @SCN-POS-005',
        '    Scenario: Works',
        '      Given a step',
      ]);

      expect(
        parsed.metadata.locationOf(MetadataField.id, 'FEAT-POS-005'),
        isNotNull,
        reason: 'the id is still recorded',
      );
      expect(parsed.metadata.source.line, 1);
    });
  });
}
