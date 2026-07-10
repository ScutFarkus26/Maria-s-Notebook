# Private Cloud Compute (Apple server model)

Maria's Notebook can route large AI drafting jobs (report cards, weekly
summaries) to Apple's server-side model on **Private Cloud Compute (PCC)** via
the FoundationModels framework. PCC keeps the same privacy guarantees as the
on-device model — stateless, no prompts stored, independently verifiable — but
offers a much larger context window (32K vs 8K) and optional reasoning.

## How it's wired up

- `Services/AI/PrivateCloudModelClient.swift` wraps `PrivateCloudComputeLanguageModel`
  and conforms to `MCPClientProtocol`, mirroring `LocalModelClient`.
- `AIClientRouter` cascade for "Apple First (Auto)" is now:
  **on-device → Private Cloud Compute → Claude**. There is also a direct
  "Apple Private Cloud" model option per feature area.
- `AppleIntelligenceSheet` sends template drafts on-device when the input fits a
  quality draft, and to PCC (reasoning `.moderate`) when it doesn't — with each
  path falling back to the other on failure (e.g. PCC daily quota reached).
- Availability is checked at runtime (`PrivateCloudModelClient.isAvailable`).
  When PCC is unavailable for any reason, routing silently falls back, so the
  app is fully functional without it.

## Activating PCC (one-time, requires Apple approval)

PCC uses a **managed entitlement**, so it is intentionally *not* in
`Maria_s_Notebook.entitlements` yet — adding a managed entitlement that isn't in
the provisioning profile breaks code-signing on every dev build.

1. Request access at <https://developer.apple.com/private-cloud-compute/>.
   (Free of cloud API cost for App Store Small Business Program apps with under
   2M first-time downloads — Maria's Notebook qualifies.)
2. After approval, in Xcode → target → **Signing & Capabilities**, add the
   **Private Cloud Compute** capability. Xcode adds the entitlement and updates
   the provisioning profile.
3. Confirm `Maria_s_Notebook.entitlements` now contains:
   ```xml
   <key>com.apple.developer.private-cloud-compute</key>
   <true/>
   ```
4. Build and run. Settings → AI Features → Apple Intelligence shows a
   **Private Cloud Compute: Available** row when it's live on the device
   (needs Apple Intelligence enabled + a network connection).

No source changes are needed — the code path is already in place and gated on
runtime availability.
