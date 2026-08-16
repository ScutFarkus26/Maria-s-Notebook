# Private Cloud Compute (Apple server model)

Maria's Notebook can use Apple's server-side model on **Private Cloud Compute
(PCC)** for deliberately chosen jobs such as long report-card drafts. PCC is
stateless, does not retain prompts, and is independently verifiable, while
offering a larger context window and optional reasoning than the on-device
model.

PCC is not an automatic destination by default. Student records move from the
device to PCC only after one of two explicit choices:

1. The school turns on **Allow Automatic Apple Private Cloud** in AI Settings.
2. The guide directly selects **Apple Private Cloud** for a feature area.

Raw classroom capture and observation reflection are always on-device. They do
not use PCC even when automatic PCC is enabled. Claude is also never a fallback
from PCC or any other Apple model; it must be selected explicitly and uses a
separately supplied Anthropic API key.

## How it's wired up

- `Services/AI/PrivateCloudModelClient.swift` wraps `PrivateCloudComputeLanguageModel`
  and conforms to `MCPClientProtocol`, mirroring `LocalModelClient`.
- `AIClientRouter` starts "Apple Intelligence (Auto)" on-device. It may fall
  through to PCC only when `AI.allowAutomaticPrivateCloud` is on. The setting is
  off by default.
- A direct **Apple Private Cloud** selection is an explicit request and remains
  available even when automatic PCC is off.
- Drafting surfaces use PCC only when the selected model or the automatic-PCC
  permission allows it. They must not silently substitute Claude.
- Availability is checked at runtime (`PrivateCloudModelClient.isAvailable`).
  When PCC is unavailable, an explicitly selected PCC request reports that it is
  unavailable. Automatic requests stay on-device when possible; if the
  on-device model cannot finish and automatic PCC is unavailable or disallowed,
  the app reports the reason without sending the request elsewhere.

## Product and pedagogy boundary

PCC may organize records, draft language, or arrange evidence-backed planning
proposals. Its output must remain visibly AI-generated, editable, and linked to
the source records that support it. The guide decides whether to accept, revise,
or reject it.

No cloud or on-device model owns decisions about mastery, readiness, practice,
representation, or which lesson a child should receive. AI output must never
create those records automatically. Only an explicit guide choice may do so.

Enabling automatic PCC is therefore a school privacy decision, not a technical
optimization. Settings copy must explain that enabling it allows automatic mode
to process student records on Apple's private servers. Turning it off restores
the on-device-only automatic boundary immediately; it does not disable an
explicit Apple Private Cloud selection.

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
5. Decide at the school level whether to enable **Allow Automatic Apple Private
   Cloud**. Leave it off to keep all automatic requests on-device. Guides can
   still select Apple Private Cloud directly for an intentional, visible job.

No source changes are needed — the code path is already in place and gated on
runtime availability.
