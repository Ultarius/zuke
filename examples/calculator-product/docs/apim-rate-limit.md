# Enforcing the rate limit with Azure API Management

The Calculator Product example uses a local Dart middleware because the
repository does not deploy an external gateway. A production service deployed
behind Azure API Management can move the same control to the APIM inbound
policy.

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
