# Untrusted pre-truthful v2 records

This directory preserves the original v2 record byte-for-byte for audit
purposes. Its payload has empty assurance and evidence arrays and its signer is
not trusted by the current trust bundle. It is **not** a valid predecessor of a
truthful Specguard v2 release record.

The independent verifier reads only `assurance-history/v2/`. A new v2 genesis
may be created there only after an eligible report, current lock, fresh
execution evidence, real external attestation, and trusted external signer are
available.
