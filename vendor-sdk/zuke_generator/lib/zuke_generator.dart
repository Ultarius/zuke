/// V2 generation package boundary.
library;

final class GenerationRequest {
  final String workspaceRoot;
  final String outputDirectory;

  const GenerationRequest({required this.workspaceRoot, required this.outputDirectory});
}
