# Changelog

## 0.2.3

- Rejected a package path claimed by two different packages and moved lexical path normalization here.
- Examples tables now continue across comments and blank lines instead of silently dropping later rows.
- Added `GherkinScenario.declaredTags`, which includes tags on Examples blocks.
- Doc string content is no longer read as tags, Examples blocks, structural keywords, or metadata markers.
- An unclosed doc string is now a parse error at its opening delimiter, instead of silently hiding the rest of the file.
- Doc strings support media types such as `"""json` and deliver the same content with LF, CRLF, or CR line endings.
- A second doc string on one step is now a parse error, instead of silently replacing the first.
- Examples tables can name rows with a reserved `caseId` column. Values must be unique lowercase kebab-case within a scenario.

## 0.2.2

- Read `contractOutput` and `contractExport` from any configured extraction
  target, including backend and custom targets.
- Added typed workspace coverage, tooling, lock, evidence, and execution
  profile models with explicit defaults and validation.
- Preserved forward-compatible extension keys while surfacing unknown
  configuration keys as structured warnings.

## 0.2.1

- Read generated contract output and export paths from the configured target,
  rather than assuming a Flutter target exists.

## 0.2.0

- Added strict schemaVersion 3 workspace configuration with stable targets,
  package identities, runner source identities, and profile lock settings.

## 0.1.1

- Improved public API documentation and package examples.

## 0.1.0

- Initial public preview release.
