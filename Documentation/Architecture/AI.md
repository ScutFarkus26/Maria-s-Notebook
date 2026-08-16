# AI in Maria's Notebook

How the app's AI features are built, where they live, and how to extend them.

> **Last updated:** 2026-07-14 (on-device classroom capture and evidence-linked AI policy)

---

## 1. Plain-English overview

Maria's Notebook uses AI to save the guide time on writing and lookups — drafting
parent emails and report cards, summarizing observations, suggesting note tags,
turning plain-English commands into records, describing photos of student work,
and answering questions about the classroom.

The guiding principle is **Apple Intelligence on device by default**. Automatic
requests stay on the device unless the school explicitly turns on automatic
Apple Private Cloud Compute in Settings. If the on-device model cannot complete
a request while that permission is off, the app stops and explains why; it does
not silently move student records to any cloud model.

There are two deliberate ways to use Apple's Private Cloud Compute (PCC):

1. A school turns on **Allow Automatic Apple Private Cloud**, permitting
   automatic mode to fall back from the on-device model to PCC.
2. A guide explicitly chooses **Apple Private Cloud** for a feature area.

PCC is Apple's larger server model for jobs such as long report-card drafts. It
does not require an API key, but it needs a network connection and an
Apple-granted entitlement (see §8). Claude (Anthropic's cloud model) is also an
explicit model choice only and requires the guide's own API key. It is never a
hidden fallback.

Some classroom workflows have a stricter boundary regardless of the general
setting: raw classroom capture and observation reflection run only on the
on-device model. If it is unavailable, those workflows remain manual.

AI organizes and reflects; the guide decides. AI-created plans, narratives,
follow-ups, and capture interpretations are always visibly labeled, editable,
and reviewable against the records that support them. AI must never decide that
a child has mastered material, is ready for a lesson, needs practice, or should
receive a particular follow-up unless the guide explicitly records that choice.

---

## 2. Providers & the routing cascade

All AI calls go through a single protocol, `MCPClientProtocol`
(`Services/MCPClient.swift`), so callers never talk to a model directly. The
implementations:

| Provider | Type | File | Notes |
|----------|------|------|-------|
| Apple On-Device | `LocalModelClient` | `Services/AI/LocalModelClient.swift` | Wraps `SystemLanguageModel.default`. Also hosts the tool-enabled chat path. |
| Apple Private Cloud | `PrivateCloudModelClient` | `Services/AI/PrivateCloudModelClient.swift` | Wraps `PrivateCloudComputeLanguageModel`. Adds `generateDraft(reasoning:)`. |
| Claude | `AnthropicAPIClient` | `Services/AnthropicAPIClient.swift` | REST client; API key in Keychain. Real streaming + multi-turn. |
| Router | `AIClientRouter` | `Services/AI/AIClientRouter.swift` | Implements `MCPClientProtocol`; dispatches to the above. |

`AIClientRouter` is the only client most code holds. It reads the guide's
per-feature model choice and routes accordingly. Automatic ("Apple Intelligence")
mode begins on-device:

```
on-device
(LocalModelClient)
    │
    └── only when the school has enabled automatic PCC ──→ Private Cloud Compute
                                                           (PrivateCloudModelClient)
```

When `AI.allowAutomaticPrivateCloud` is off (the default), an on-device failure
returns an availability/privacy explanation instead of falling through to PCC.
When it is on, an unavailable or unsuccessful on-device request may fall through
to PCC. Selecting `.applePrivateCloud` directly is an explicit request and does
not depend on the automatic-PCC toggle. If the selected Apple provider fails,
the router returns an Apple Intelligence availability error. It never changes
the request to Claude on its own.

> **History:** A local **Ollama** provider existed before the WWDC26 work and
> was removed — Apple's on-device + PCC models now fill that "local, private"
> role. If you find stray `ollama` references, they're stale.

---

## 3. Per-feature model selection

AI is configured **per feature area**, not globally, so the guide can keep chat
on-device but send lesson planning to Claude. Defined in
`Settings/AIModelSettingsView.swift`.

`AIFeatureArea` (the surfaces) and their defaults:

| Area | Purpose | Default model |
|------|---------|---------------|
| `.chat` | Conversational "Ask AI" assistant | Apple Intelligence (Auto) |
| `.lessonPlanning` | Curriculum planning recommendations | Apple Intelligence (Auto) |
| `.backgroundTasks` | Note suggestions, drafting, analysis | Apple Intelligence (Auto) |

`AIModelOption` (the choices): `.localFirstAuto` (cascade), `.appleOnDevice`,
`.applePrivateCloud`, `.claudeSonnet`, `.claudeHaiku`. Selections persist in
`UserDefaults` and are read by `AIFeatureArea.resolvedModel()`. Claude options
report `requiresAPIKey == true`; the Apple options report `isPrivate == true`.

`Allow Automatic Apple Private Cloud` is a separate, school-level privacy
permission. It is stored as `AI.allowAutomaticPrivateCloud`, defaults to off,
and controls only `.localFirstAuto`. It does not prevent a guide from explicitly
selecting Apple Private Cloud. Changing this permission should be an informed
school choice because it changes where student records are processed.

A service tells the router which area it's serving via
`mcpClient.configureForFeature(.chat)` before each call.

---

## 4. The AI features

Every feature is gated behind `#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)`
(see §8) and checks `SystemLanguageModel.default.isAvailable` (or the PCC
equivalent) at runtime before calling the model.

| Feature | File | Output | Streaming | Multimodal |
|---------|------|--------|-----------|------------|
| Draft generation (parent email, report card, action plan, weekly summary) | `Components/AppleIntelligenceSheet.swift` + `…+Generation.swift` | Free text | No | — |
| Meeting summaries | `Students/Meetings/MeetingSummaryGenerator.swift` | `@Generable` `MeetingSummary` | Yes | — |
| Observation reflection / narrative draft | `Notes/Observations/ObservationsView+AI.swift` | Evidence-linked `@Generable` `NotesDigest` / `NotesNarrative` | No | — |
| Note tag + student suggestion | `Notes/Editor/NoteEditorAISuggestion.swift` | `@Generable` `NoteTagSuggestion` | No | **Photo** |
| Describe photo into note | `Notes/Editor/NoteEditorAISuggestion.swift` | Free text | No | **Photo** |
| Story metadata (title/themes/grade) | `Stories/StoryAnalyzer.swift` | `@Generable` `StoryAnalysisAI` | No | **PDF pages** |
| Todo smart parsing | `Todos/Services/TodoSmartParserService.swift` | `@Generable` `ParsedTodo` | No | — |
| Student-name extraction | `Todos/Services/TodoStudentSuggestionService.swift` | `@Generable` `ExtractedNames` | No | — |
| Command bar parsing and classroom capture proposal | `Services/CommandBar/AppleIntelligenceCommandParser.swift` | `@Generable` `ParsedTeacherCommand` / `GeneratedClassroomCapture` | No | — |
| Ask-your-notebook chat | `Chat/Services/ChatService.swift` + `Services/AI/NotebookTools.swift` | Free text | Yes | — |
| Lesson planning | `Planning/AIPlanning/LessonPlanning/*` | Structured | — | — |

The command bar first uses deterministic keyword/fuzzy parsing, then asks the
on-device Apple Intelligence model when the result is uncertain. It never makes
a hidden Claude request.

**Raw classroom capture is on-device and review-first.** The structured capture
parser receives the guide's account and local candidate names, then returns an
editable proposal. It has no Core Data access and cannot save by itself. It must
ground each observation and next step in words the guide actually supplied;
unsupported interpretations are discarded. The guide reviews the proposed
lesson, children, observations, and explicitly stated follow-ups before any
record is created. The parser never falls back to PCC or Claude.

**Observation reflection is on-device and source-linked.** It presents factual
observations, repeated patterns to review, and questions for future observation.
Each finding carries references to the local records used to support it. A
separate deterministic check identifies presentations without a linked
observation; this is a record-completeness check, not an AI conclusion. The
reflection does not infer sentiment, mastery, motivation, diagnosis, or
readiness, and it never falls back to a cloud model.

**Lesson planning is proposal-based.** Curriculum rules and local records
assemble eligible lesson candidates. AI may help arrange or explain those
candidates, but the UI shows evidence availability and links back to source
records rather than presenting an AI confidence score as truth. The guide can
edit, accept, or reject every recommendation. No recommendation becomes a
presentation, assignment, or practice record until the guide chooses it.

System prompts/personas for all of this live in one place: `AppCore/AIPrompts.swift`
(`generalAssistant`, `advancedAssistant`, `lessonPlanningAssistant`,
`chatAssistant`, `commandBarParser`, `noteClassification`).

---

## 5. Key building blocks

**Sessions.** A call is a `LanguageModelSession(model:tools:instructions:)` then
`respond(to:)` (one-shot) or `streamResponse(to:)` (incremental). Pass a
`SystemLanguageModel` for on-device or a `PrivateCloudComputeLanguageModel` for
PCC.

**Structured output (`@Generable`).** Types tagged `@Generable` with `@Guide`
field hints are produced directly by the model — no JSON parsing. Example:
`StoryAnalysisAI` in `Stories/StoryAnalyzer.swift`. Prefer this over
free-text-then-parse whenever the shape is known.

**Reasoning level (PCC).** `PrivateCloudModelClient.generateDraft(…, reasoning:)`
passes `ContextOptions(reasoningLevel:)` (`.light`/`.moderate`/`.deep`) so big
drafts can "think" more. On-device doesn't support this.

**Token budgeting.** `Services/AI/TokenBudget.swift` measures input against the
model's real context window using `SystemLanguageModel.tokenCount(for:)` and
`contextSize` (iOS 26.4+). Use `budget.fits(prompt:reserving:)` to decide
on-device-vs-PCC, and `budget.prefix(of:fittingTokens:)` to clamp long input
(replaces the old "guess by character count" truncation). `AppleIntelligenceSheet`
uses `fits` to send oversized drafts to PCC; `StoryAnalyzer` uses `prefix` to
clamp PDF text.

**Image understanding.** Attach a `CGImage`/`UIImage`/`NSImage`/file URL to a
prompt with `Attachment(image)` inside a `respond { … }` prompt builder. Only
available when `SystemLanguageModel.default.capabilities.contains(.vision)` — always
gate on this. Two uses today:
- Note photos: `NoteEditorAISuggestion.noteImageForAI` loads a downsampled
  `CGImage` (`PhotoStorageService.loadCGImageForAI`) for tag suggestion and the
  "Describe Photo" action.
- Story PDFs with no text layer: `StoryAnalyzer.analyzeVisually(url:)` renders
  the first pages with PDFKit and sends them as attachments.

**Notebook tools (on-device retrieval).** `Services/AI/NotebookTools.swift` defines
`FoundationModels.Tool`s the chat model can call to look things up in the guide's
own data: `SearchNotebookTool` (keyword search via `SearchIndexService`) and
`StudentNotesTool` (a student's recent notes from Core Data). They're attached in
`LocalModelClient.sendConversation`/`streamConversation`, which give chat a real
tool-enabled multi-turn session instead of flattening messages into one prompt.
Tool results retain source references so an answer can show which notebook
records support it. Retrieved text is evidence for a proposed answer, not
authority to make a guide-owned pedagogical decision.

---

## 6. Privacy model

- **On-device is the default boundary.** Automatic AI stays on the device unless
  the school explicitly enables automatic PCC. Raw classroom capture and
  observation reflection stay on-device in all cases.
- **PCC is permitted only by an explicit choice.** That can be the school-level
  automatic-PCC permission or the guide directly selecting Apple Private Cloud
  for a feature. PCC is stateless (no prompts retained) and independently
  verifiable; Apple does not use the input to train foundation models.
- **Claude sends data to Anthropic** and requires the user's own API key (stored
  in the Keychain, never in the binary). It is opt-in per feature and is never a
  fallback from an Apple provider.
- `AppleIntelligenceSheet` has an **anonymize** toggle that strips student names
  from the context before drafting (`SmartNoteFormatter(anonymize:)`).
- Test/sample students are filtered out of AI context (`TestStudentsFilter`).
- AI proposals expose their status and supporting records, remain editable, and
  require guide confirmation before they create or change classroom records.
- The model may organize evidence and draft language, but it may not diagnose a
  child or decide mastery, readiness, practice, representation, or a next lesson.

When choosing where new AI work should run, begin on-device and collect the
minimum student data needed. Cloud processing requires a visible, explicit
choice. A new workflow that interprets raw observation or capture data should
remain on-device unless this architecture decision is deliberately revisited.

---

## 7. Availability & graceful fallback

Always assume the model may be unavailable. Reasons surface as:

- `SystemLanguageModel.default.availability` → `.appleIntelligenceNotEnabled`,
  `.deviceNotEligible`, `.modelNotReady`.
- `PrivateCloudComputeLanguageModel.availability` → `.deviceNotEligible`,
  `.systemNotReady` (covers missing entitlement / offline).
- Generation errors map through `LanguageModelError` → `LocalModelError`
  (`contextSizeExceeded`, `rateLimited`, `refusal`, `timeout`, …).

UI surfaces availability in **Settings → AI Features → Apple Intelligence**, which shows
separate **On-Device** and **Private Cloud Compute** status rows
(`AppleIntelligenceStatusRow` in `Settings/SettingsView.swift`). Features hide or
disable their AI buttons when the relevant capability is absent. The model
settings also explain whether automatic PCC is allowed. On-device-only classroom
workflows say that records were not sent elsewhere when generation cannot run.

---

## 8. Build flag & entitlement

**`ENABLE_FOUNDATION_MODELS`** — all FoundationModels code is compiled behind this
active-compilation condition (now set for Debug and Release). When off, the app
builds with stub error types and AI features fall back to system writing tools or
no-ops. This flag is documented in this section because there is no separate
build-flag document.

**Private Cloud Compute entitlement** — PCC needs the managed entitlement
`com.apple.developer.private-cloud-compute`, which Apple must grant. It is
deliberately **not** in `Maria_s_Notebook.entitlements` yet, because adding an
un-granted managed entitlement breaks code-signing on dev builds. Until it's
added, `PrivateCloudModelClient.isAvailable` is false and automatic routing stays
on-device. Activation steps: `PrivateCloudCompute.md`.

---

## 9. How to add a new AI feature

1. **Classify the data before picking a provider.** Raw classroom capture and
   observation reflection are on-device-only. For other surfaces, reuse the
   injected `AIClientRouter`; automatic PCC remains subject to the school-level
   permission. Call a provider directly only for a visible provider-specific
   feature.
2. **Define structured output** with `@Generable`/`@Guide` if the shape is known;
   otherwise request free text.
3. **Gate it** with `#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)`
   and a runtime `isAvailable` check; for images also check
   `capabilities.contains(.vision)`.
4. **Budget the input** with `TokenBudget` instead of character limits.
5. **Add the persona** to `AppCore/AIPrompts.swift` rather than inlining prompts.
6. **Make it a proposal.** Clearly label AI output, link claims to the records
   that support them, let the guide edit or reject it, and require confirmation
   before changing data. Do not turn model confidence into a readiness judgment.
7. **Handle errors** by mapping `LanguageModelError` to user-facing copy and
   degrading gracefully without silently crossing a privacy boundary.

---

## 10. File map

```
Services/
  MCPClient.swift                     # MCPClientProtocol + shared types
  AnthropicAPIClient.swift            # Claude provider
  AI/
    AIClientRouter.swift              # routing + cascade
    LocalModelClient.swift            # on-device provider + tool chat
    PrivateCloudModelClient.swift     # Private Cloud Compute provider
    TokenBudget.swift                 # token-based input budgeting
    NotebookTools.swift               # on-device search tools for chat
  CommandBar/                         # command parsing (local/AI/Claude tiers)
Chat/Services/ChatService.swift       # chat orchestration + escalation
Planning/AIPlanning/LessonPlanning/   # lesson planning service and state
Todos/Services/                       # todo parsing and student suggestions
AppCore/AIPrompts.swift               # all system prompts/personas
Settings/
  AIModelSettingsView.swift           # AIFeatureArea, AIModelOption, picker
  SettingsView.swift                  # Apple Intelligence status rows
Components/
  AppleIntelligenceSheet.swift        # draft generation UI
  AppleIntelligenceSheet+Generation.swift  # on-device/PCC draft routing
Notes/
  Observations/ObservationsView+AI.swift  # observation digests/narrative
  Editor/NoteEditorAISuggestion.swift     # tags + photo description
Stories/StoryAnalyzer.swift           # story metadata (text + visual)
Documentation/Architecture/
  AI.md                               # this file
  PrivateCloudCompute.md              # PCC entitlement activation
```
