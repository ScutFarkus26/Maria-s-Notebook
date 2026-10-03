# AI in Cosmic Daybook

How the app's AI features are built, where they live, and how to extend them.

> **Last updated:** 2026-07-14 (on-device classroom capture and evidence-linked AI policy)

---

## 1. Plain-English overview

Cosmic Daybook uses AI to save the guide time on writing and lookups — drafting
parent emails and report cards, summarizing observations, suggesting note tags,
turning plain-English commands into records, describing photos of student work,
and answering questions about the classroom.

The guiding principle is **Apple Intelligence on device by default**. Automatic
requests stay on the device unless the school explicitly turns on automatic
Apple Private Cloud Compute in Settings. If the on-device model cannot complete
a request while that permission is off, the app stops and explains why; it does
not silently move student records to any cloud model.

The app's own AI is Apple Intelligence only (since 2026-09-26). The one way
work reaches Apple's Private Cloud Compute (PCC) is a school turning on
**Allow Apple Private Cloud**, which lets a request the on-device model can't
finish fall back to PCC.

PCC is Apple's larger server model for jobs such as long report-card drafts. It
does not require an API key, but it needs a network connection and an
Apple-granted entitlement (see §8). The app has no Claude or OpenAI client and
stores no API keys; Claude works with the notebook only from outside, over the
MCP server (see `MCP_SERVER.md`).

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
| Router | `AIClientRouter` | `Services/AI/AIClientRouter.swift` | Implements `MCPClientProtocol`; dispatches to the above. |

`AIClientRouter` is the only client most code holds. Every request begins
on-device:

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
to PCC. If neither can serve it, the router returns an Apple Intelligence
availability error. `AIClientRouter.isAvailable` answers whether a request could
be served now; screens use it to enable or explain their AI buttons.

> **History:** A local **Ollama** provider existed before the WWDC26 work and
> was removed — Apple's on-device + PCC models now fill that "local, private"
> role. If you find stray `ollama` references, they're stale.

---

## 3. The one setting

There is no per-feature model choice. `Allow Apple Private Cloud`
(`Settings/PrivateCloudSettingsView.swift`) is a school-level privacy
permission, stored as `AI.allowAutomaticPrivateCloud` and off by default.
Changing it should be an informed school choice because it changes where
student records are processed.

> **History:** until 2026-09-26 each feature area (chat, lesson planning,
> background tasks) had its own picker offering Apple On-Device, Apple Private
> Cloud, Apple Auto, Claude Sonnet and Claude Haiku, with the guide's Anthropic
> key; story covers could use OpenAI `gpt-image-1`. All of it was removed.
> Old `AI.chatModel` / `AI.lessonPlanningModel` / `AI.backgroundTasksModel`
> values and Keychain keys may linger on devices; nothing reads them.

---

## 4. The AI features

Every feature is gated behind `#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)`
(see §8) and checks `SystemLanguageModel.default.isAvailable` (or the PCC
equivalent) at runtime before calling the model.

| Feature | File | Output | Streaming | Multimodal |
|---------|------|--------|-----------|------------|
| Draft generation (parent email, report card, action plan, weekly summary) | `Students/Notes/AppleIntelligenceSheet.swift` + `…+Generation.swift` | Free text | No | — |
| Meeting summaries | `Students/Meetings/MeetingSummaryGenerator.swift` | `@Generable` `MeetingSummary` | Yes | — |
| Observation reflection / narrative draft | `Notes/Observations/ObservationsView+AI.swift` | Evidence-linked `@Generable` `NotesDigest` / `NotesNarrative` | No | — |
| Note tag + student suggestion | `Notes/Editor/NoteEditorAISuggestion.swift` | `@Generable` `NoteTagSuggestion` | No | **Photo** |
| Describe photo into note | `Notes/Editor/NoteEditorAISuggestion.swift` | Free text | No | **Photo** |
| Story metadata (title/themes/grade) | `Stories/StoryAnalyzer.swift` | `@Generable` `StoryAnalysisAI` | No | **PDF pages** |
| Command bar parsing and classroom capture proposal | `CommandBar/Services/AppleIntelligenceCommandParser.swift` | `@Generable` `ParsedTeacherCommand` / `GeneratedClassroomCapture` | No | — |
| Ask-your-notebook chat | `Chat/Services/ChatService.swift` + `Services/AI/NotebookTools.swift` | Free text | Yes | — |
| Lesson planning | `Planning/AIPlanning/LessonPlanning/*` | Structured | — | — |
| Story ↔ lesson connections (rerank + one-line reasons) | `Stories/StoryLessonMatcher.swift` | JSON via `generateStructuredJSON` | No | — |
| Parsha ↔ album lesson suggestions | `Parsha/Services/ParshaSuggestionService.swift` | JSON via `generateStructuredJSON` | No | — |
| Story cover | `Stories/StoryCoverGenerator.swift` | Image Playground image | — | — |

The command bar first uses deterministic keyword/fuzzy parsing, then asks the
on-device Apple Intelligence model when the result is uncertain.

**Raw classroom capture is on-device and review-first.** The structured capture
parser receives the guide's account and local candidate names, then returns an
editable proposal. It has no Core Data access and cannot save by itself. It must
ground each observation and next step in words the guide actually supplied;
unsupported interpretations are discarded. The guide reviews the proposed
lesson, children, observations, and explicitly stated follow-ups before any
record is created. The parser never falls back to PCC.

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

**Meeting and follow-up tools.** `Services/AI/NotebookTools+Meetings.swift` adds
four more: `recordStudentMeeting`, `addFollowUp`, `resolveFollowUp` and
`listOpenFollowUps`. They are thin bridges onto the MCP handlers
(`MCPNotebookTools.recordMeeting` / `addFollowUp` / `resolveFollowUp` /
`listOpenFollowUps`), so chat and Claude share one save path and one wording.
Chat has no per-call approval, so the three writers' descriptions limit them to
an explicit request from the guide, and expected failures come back as replies
rather than thrown errors. `addFollowUp` drops the MCP duplicate notice's
"pass force: true" clause, since chat has no `force`.

---

## 6. Privacy model

- **On-device is the default boundary.** Automatic AI stays on the device unless
  the school explicitly enables automatic PCC. Raw classroom capture and
  observation reflection stay on-device in all cases.
- **PCC is permitted only by an explicit choice:** the school-level
  Allow Apple Private Cloud permission. PCC is stateless (no prompts retained) and independently
  verifiable; Apple does not use the input to train foundation models.
- **No third-party model inside the app.** Claude sees notebook data only
  through the MCP server, which the guide turns on in Settings → AI.
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
deliberately **not** in `CosmicDaybook.entitlements` yet, because adding an
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
  AI/
    AIClientRouter.swift              # routing + cascade
    LocalModelClient.swift            # on-device provider + tool chat
    PrivateCloudModelClient.swift     # Private Cloud Compute provider
    TokenBudget.swift                 # token-based input budgeting
    NotebookTools.swift               # on-device search tools for chat
    NotebookTools+Meetings.swift      # chat bridges onto the MCP meeting/follow-up tools
  CommandBar/                         # command parsing (local and on-device tiers)
Chat/Services/ChatService.swift       # chat orchestration + escalation
Planning/AIPlanning/LessonPlanning/   # lesson planning service and state
Todos/Services/                       # todo parsing and student suggestions
AppCore/AIPrompts.swift               # all system prompts/personas
Settings/
  PrivateCloudSettingsView.swift      # the Allow Apple Private Cloud toggle
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
