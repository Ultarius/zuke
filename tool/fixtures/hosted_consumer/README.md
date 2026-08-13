# Hosted consumer certification fixture

This is a template, not a user project and not a second source of package
versions. The framework release matrix renders it into a temporary directory
outside the Zuke checkout with exact hosted package versions and compatibility
identities.

The certification runner proves that a clean consumer can resolve the
published package tuple, generate its scenario contract, run the same test
unmanaged and under Zuke, validate every official profile, generate and check
profile locks, and execute the all-profile gate. It rejects path dependencies,
Git dependencies, dependency overrides, workspace inheritance, private
packages, and stale package versions.
