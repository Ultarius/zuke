import 'package:test/test.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:zuke_cli/src/proof_engine.dart';

void main() {
  group('IdentityValidator title lint', () {
    test(
      'reports ZUKE-ID-010 warning when Feature title contains the FEAT-* ID',
      () {
        final discovery = WorkspaceDiscoveryResult(
          config: const ZukeConfig(),
          data: MetadataExtractorResult(
            features: [
              ParsedFeature(
                tags: [],
                featureElement: const GherkinElement(
                  keyword: GherkinKeyword.feature,
                  title: 'FEAT-FOO-001 Feature Title Contains ID',
                  source: SourceLocation(file: 'a.feature', line: 1),
                ),
                metadata: const ParsedMetadata(
                  id: 'FEAT-FOO-001',
                  source: SourceLocation(file: 'a.feature', line: 1),
                ),
                rules: [],
              ),
            ],
          ),
        );
        final result = IdentityValidator().validate(discovery);
        final warning = result.errors.singleWhere(
          (message) => message.code == 'ZUKE-ID-010',
        );
        expect(warning.severity, Severity.warning);
      },
    );

    test(
      'reports ZUKE-ID-010 warning when Rule title contains the RULE-* ID',
      () {
        final discovery = WorkspaceDiscoveryResult(
          config: const ZukeConfig(),
          data: MetadataExtractorResult(
            features: [
              ParsedFeature(
                tags: [],
                featureElement: const GherkinElement(
                  keyword: GherkinKeyword.feature,
                  title: 'Feature One',
                  source: SourceLocation(file: 'a.feature', line: 1),
                ),
                metadata: const ParsedMetadata(
                  id: 'FEAT-FOO-001',
                  source: SourceLocation(file: 'a.feature', line: 1),
                ),
                rules: [
                  ParsedRule(
                    tags: [
                      const GherkinTag(
                        name: 'RULE-FOO-001',
                        source: SourceLocation(file: 'a.feature', line: 5),
                      ),
                    ],
                    ruleElement: const GherkinElement(
                      keyword: GherkinKeyword.rule,
                      title: 'RULE-FOO-001 Rule Title Contains ID',
                      source: SourceLocation(file: 'a.feature', line: 5),
                    ),
                    metadata: const ParsedMetadata(
                      id: 'RULE-FOO-001',
                      source: SourceLocation(file: 'a.feature', line: 5),
                    ),
                    scenarios: [],
                  ),
                ],
              ),
            ],
          ),
        );
        final result = IdentityValidator().validate(discovery);
        final warning = result.errors.singleWhere(
          (message) => message.code == 'ZUKE-ID-010',
        );
        expect(warning.severity, Severity.warning);
      },
    );

    test('passes without warning when Feature title is prose-only', () {
      final discovery = WorkspaceDiscoveryResult(
        config: const ZukeConfig(),
        data: MetadataExtractorResult(
          features: [
            ParsedFeature(
              tags: [],
              featureElement: const GherkinElement(
                keyword: GherkinKeyword.feature,
                title: 'Feature One',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              metadata: const ParsedMetadata(
                id: 'FEAT-FOO-001',
                source: SourceLocation(file: 'a.feature', line: 1),
              ),
              rules: [
                ParsedRule(
                  tags: [
                    const GherkinTag(
                      name: 'RULE-FOO-001',
                      source: SourceLocation(file: 'a.feature', line: 5),
                    ),
                  ],
                  ruleElement: const GherkinElement(
                    keyword: GherkinKeyword.rule,
                    title: 'Rule title is prose only',
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  metadata: const ParsedMetadata(
                    id: 'RULE-FOO-001',
                    source: SourceLocation(file: 'a.feature', line: 5),
                  ),
                  scenarios: [],
                ),
              ],
            ),
          ],
        ),
      );
      final result = IdentityValidator().validate(discovery);
      expect(result.errors.where((e) => e.code == 'ZUKE-ID-010'), isEmpty);
    });
  });
}
