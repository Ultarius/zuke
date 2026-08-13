import 'dart:convert';

import 'canonical_json.dart';

/// Immutable signing domains. A domain change is a breaking artifact change
/// and must be called out in migration documentation and changelogs.
const releaseSigningDomain = 'Zuke behavioral assurance release\u0000';
const attestationSigningDomain = 'Zuke external control attestation\u0000';

List<int> releaseSigningPayload(Map<String, Object?> unsigned) =>
    utf8.encode('$releaseSigningDomain${canonicalJson(unsigned)}');

List<int> attestationSigningPayload(Map<String, Object?> unsigned) =>
    utf8.encode('$attestationSigningDomain${canonicalJson(unsigned)}');
