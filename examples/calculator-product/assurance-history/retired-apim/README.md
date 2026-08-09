# Retired APIM fixture

The gateway attestation in this directory is retained byte-for-byte as
historical fixture data. It describes an APIM deployment that is not part of
this repository and is not read by the Calculator workspace, its lock, or its
GitHub Actions workflows.

The active example now proves its application-owned rate limiter through local
HTTP integration evidence. If a real APIM deployment is introduced later, its
policy export must be collected from that environment and signed through the
authorized release-signing workflow before it is used as external assurance.
