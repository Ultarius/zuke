# Zuke adversarial conformance catalog

This directory indexes executable adversarial cases that are deliberately kept
next to the production package they exercise. The catalog is discoverable from
the conformance package without copying cryptographic or graph fixtures into a
second implementation.

Each entry names the owning test, the expected failure class, and whether a
failure blocks assurance eligibility. Test discovery in `conformance_test.dart`
validates this catalog so a referenced test cannot silently disappear.
