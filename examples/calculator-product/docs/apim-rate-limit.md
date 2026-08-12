# Enforcing the rate limit with Azure API Management

The Calculator Product example uses a local Dart middleware because the
repository does not deploy an external gateway. A production service deployed
behind Azure API Management can move the same control to the APIM inbound
policy.

## What the checked-in example proves

The active example has only `flutter` and `backend` targets in
`zuke.yaml`. The request path is:

```text
HTTP client
    |
    v
CalculatorServer
    |
    v
RateLimitMiddleware (@ProvidesControl: CTRL-CALC-RATE-LIMIT)
    |
    +--> HTTP 429 + Retry-After when the identity budget is exhausted
    |
    v
Calculator controller and domain service
```

The API integration test sends real requests through this path. It verifies
the accepted requests, the rejected request, the retry header, the fact that
the rejected request does not reach the controller, and the fact that another
identity remains allowed. Zuke then combines the source graph with the test
evidence and records the application-owned control as `proven`.

This is why the example does not contain an `edge` target. The following
configuration is an external-attestation extraction target, not an APIM
deployment:

```yaml
targets:
  edge:
    language: external
    extractor: attestation
```

By itself, that target would not install a gateway, route traffic, call Azure,
or create a signed record. It is meaningful only when an external provider,
attestation document, trust bundle, and matching control metadata are also
configured. Keeping an unused target in this local-only example implied that
APIM was active when it was not.

## Example policy

Apply this policy to the API or operation that exposes
`/v1/calculations/evaluate`:

```xml
<policies>
  <inbound>
    <base />
    <rate-limit-by-key
      calls="2"
      renewal-period="60"
      counter-key="@(context.Request.Headers.GetValueOrDefault(&quot;x-rate-limit-identity&quot;, context.Request.IpAddress))"
      retry-after-header-name="Retry-After" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
```

This uses the request identity header when it is present and falls back to the
caller IP address. In a real deployment, prefer a trusted subscription,
consumer, or authenticated-user identifier rather than allowing an arbitrary
client to choose its own identity header.

The APIM `rate-limit-by-key` policy returns HTTP 429 when the configured call
rate is exceeded. Its counters are maintained by APIM and can be affected by
distributed gateway behavior, so production tests should allow for the
platform's documented throttling characteristics:

<https://learn.microsoft.com/en-us/azure/api-management/rate-limit-by-key-policy>

## Choosing the enforcement owner

Do not silently claim both implementations are the same control. Choose one of
these deployment arrangements:

- **Application-owned:** keep `RateLimitMiddleware`, keep the control as
  `ingress-dominance`/`proven`, and use the checked-in local HTTP evidence.
- **APIM-owned:** deploy the APIM policy, make APIM the authoritative boundary,
  and change the application's Zuke control metadata to an external control
  requiring a fresh signed APIM attestation. The attestation should identify
  the policy export digest, API route, APIM revision, signer, and expiry.
- **Defense in depth:** retain the application middleware as a separate,
  lower-level fallback and model the APIM policy as a second control. This can
  be useful, but the two budgets and identities must be documented because a
  request may be rejected by either layer.

When APIM is authoritative, do not use the local demonstration as evidence of
the APIM deployment. Run an APIM integration test against the deployed gateway
and collect the policy export through the authorized release-signing workflow.
The local GitHub Actions job can still run the application tests, while the
release gate verifies the signed external evidence.

## What an APIM integration adds

An APIM-owned control has a different evidence path:

1. APIM enforces the inbound policy before the request reaches the backend.
2. An integration test sends requests through the deployed APIM endpoint and
   records the observed 429 and `Retry-After` behavior.
3. The deployment process exports the APIM policy and hashes the export and
   route scope.
4. The authorized signing workflow creates a
   `kind: zuke.external-attestation` record containing the provider, target,
   policy digest, route scope, signer, issue time, and expiry.
5. Zuke verifies the signature against the attestation trust usage, checks the
   document and policy scope, and includes the attestation in the release
   lock.
6. A release gate rejects the deployment when the attestation is missing,
   expired, signed by an untrusted key, or no longer matches the APIM export.

The deployment-only configuration has the following conceptual shape. It is
an overlay for a real APIM workspace, not a change to this checked-in example:

```yaml
targets:
  edge:
    language: external
    extractor: attestation

# The exact provider file is project-specific. It must associate the APIM
# provider with an external control and a confined attestation document.
providers:
  - id: calculator-apim-rate-limit
    provides: CTRL-CALC-RATE-LIMIT-APIM
    assurance: attested
    target: edge
    variant: default
    kind: rate-limit
    layer: edge
    system: azure-api-management
    document: attestations/calculator-apim-rate-limit.json
```

The provider metadata must agree with the signed document. The signed document
must be produced from the real APIM environment by the authorized signing
workflow; a local mock, a copied policy, or a hand-edited JSON file is not
valid production evidence.

## How this relates to Zuke

The behavioral contract remains the same:

| Contract | Local example | APIM deployment |
| --- | --- | --- |
| Per-identity budget | `RateLimitMiddleware` | `rate-limit-by-key` |
| Rejection | HTTP 429 | HTTP 429 |
| Retry guidance | `Retry-After: 60` | APIM retry-after header |
| Backend protection | Middleware runs before the controller | Inbound policy runs before the backend |
| Local CI proof | Dart HTTP integration test | Optional APIM integration test |

The checked-in Calculator assurance record proves the local implementation. It
does not claim that an APIM policy exists. If a deployment adopts APIM, its
release process can add a separate, signed external attestation containing the
APIM policy export, route scope, policy digest, and expiry. That attestation is
only appropriate when APIM is actually deployed and the export is obtained
from the real environment.
