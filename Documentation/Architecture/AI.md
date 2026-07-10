# AI in Maria's Notebook

How the app's AI features are built, where they live, and how to extend them.

> **Last updated:** 2026-06-14 (Foundation Models adoption — WWDC26 APIs)

---

## 1. Plain-English overview

Maria's Notebook uses AI to save the guide time on writing and lookups — drafting
parent emails and report cards, summarizing observations, suggesting note tags,
turning plain-English commands into records, describing photos of student work,
and answering questions about the classroom.

The guiding principle is **private first**. Wherever possible the work runs on
Apple's models — either fully on-device or on Apple's Private Cloud Compute, both
of which keep student data inside Apple's privacy boundary (nothing stored, no
training, independently verifiable). Claude (Anthropic's cloud model) is only
used when the guide explicitly selects it or as a last-resort fallback, and it
requires the guide's own API key.

Three "providers" sit behind every AI feature, tried in this order for the
automatic setting:

1. **Apple On-Device** — instant, free, fully private, works offline. Smaller
   context window (~8K tokens).
2. **Apple Private Cloud Compute (PCC)** — Apple's larger server model for big
   jobs (report cards, long summaries). Still private, no API key, but needs a
   network connection and an Apple-granted entitlement (see §8).
3. **Claude** — most capable for open-ended reasoning; requires the user's
   Anthropic API key and sends data to Anthropic's servers.

If a provider isn't available (no Apple Intelligence, offline, no API key, quota
reached), the app silently falls back to the next one. Nothing breaks; the
feature just uses whatever is available, or tells the user it can't run.

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

`AIClientRouter` is the only client most code holds. It reads the user's
per-feature model choice and routes accordingly. The automatic ("Apple First")
strategy cascades:

```
on-device  →  Private Cloud Compute  →  Claude
(LocalModelClient)   (PrivateCloudModelClient)   (AnthropicAPIClient)
```

Each step is skipped if that provider's `isAvailable` is false, and a thrown
`LocalModelError` falls through to the next step. Claude is the terminal
fallback.

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
| `.chat` | Conversational "Ask AI" assistant | Apple First (Auto) |
| `.lessonPlanning` | Curriculum planning recommendations | Claude Sonnet |
| `.backgroundTasks` | Note suggestions, drafting, analysis | Apple First (Auto) |

`AIModelOption` (the choices): `.localFirstAuto` (cascade), `.appleOnDevice`,
`.applePrivateCloud`, `.claudeSonnet`, `.claudeHaiku`. Selections persist in
`UserDefaults` and are read by `AIFeatureArea.resolvedModel()`. Claude options
report `requiresAPIKey == true`; the Apple options report `isPrivate == true`.

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
| Observation digests / narrative | `Components/ObservationsView+AI.swift` | `@Generable` `NotesDigest` / `NotesNarrative` | Yes | — |
| Note tag + student suggestion | `Components/UnifiedNoteEditor/NoteEditorAISuggestion.swift` | `@Generable` `NoteTagSuggestion` | No | **Photo** |
| Describe photo into note | `Components/UnifiedNoteEditor/NoteEditorAISuggestion.swift` | Free text | No | **Photo** |
| Story metadata (title/themes/grade) | `Stories/StoryAnalyzer.swift` | `@Generable` `StoryAnalysisAI` | No | **PDF pages** |
| Todo smart parsing | `Services/TodoSmartParserService.swift` | `@Generable` `ParsedTodo` | No | — |
| Student-name extraction | `Services/TodoStudentSuggestionService.swift` | `@Generable` `ExtractedNames` | No | — |
| Command bar parsing | `Services/CommandBar/AppleIntelligenceCommandParser.swift` | `@Generable` `ParsedTeacherCommand` | No | — |
| Ask-your-notebook chat | `Services/Chat/ChatService.swift` + `Services/AI/NotebookTools.swift` | Free text | Yes | — |
| Lesson planning | `Services/LessonPlanning/*` | Structured | — | — |

The command bar also has a non-AI tier-1 (`LocalCommandParser`, keyword/fuzzy)
and a Claude tier-3 (`ClaudeCommandParser`); `CommandBarService` cascades
local → Apple Intelligence → Claude.

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

**Notebook tools (on-device RAG).** `Services/AI/NotebookTools.swift` defines
`FoundationModels.Tool`s the chat model can call to look things up in the guide's
own data: `SearchNotebookTool` (keyword search via `SearchIndexService`) and
`StudentNotesTool` (a student's recent notes from Core Data). They're attached in
`LocalModelClient.sendConversation`/`streamConversation`, which give chat a real
tool-enabled multi-turn session instead of flattening messages into one prompt.

---

## 6. Privacy model

- **On-device** and **PCC** keep data inside Apple's boundary. PCC is stateless
  (no prompts retained) and independently verifiable. Neither trains on input.
- **Claude** sends data to Anthropic and requires the user's own API key (stored
  in the Keychain, never in the binary). It is opt-in per feature or a fallback.
- `AppleIntelligenceSheet` has an **anonymize** toggle that strips student names
  from the context before drafting (`SmartNoteFormatter(anonymize:)`).
- Test/sample students are filtered out of AI context (`TestStudentsFilter`).

When choosing where new AI work should run, prefer on-device → PCC → Claude, and
never send more student data than the feature needs.

---

## 7. Availability & graceful fallback

Always assume the model may be unavailable. Reasons surface as:

- `SystemLanguageModel.default.availability` → `.appleIntelligenceNotEnabled`,
  `.deviceNotEligible`, `.modelNotReady`.
- `PrivateCloudComputeLanguageModel.availability` → `.deviceNotEligible`,
  `.systemNotReady` (covers missing entitlement / offline).
- Generation errors map through `LanguageModelError` → `LocalModelError`
  (`contextSizeExceeded`, `rateLimited`, `refusal`, `timeout`, …).

UI surfaces this in **Settings → AI Features → Apple Intelligence**, which shows
separate **On-Device** and **Private Cloud Compute** status rows
(`AppleIntelligenceStatusRow` in `Settings/SettingsView.swift`). Features hide or
disable their AI buttons when the relevant capability is absent.

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
added, `PrivateCloudModelClient.isAvailable` is false and routing falls back to
Claude — no behavior change. Activation steps: `PrivateCloudCompute.md`.

---

## 9. How to add a new AI feature

1. **Pick the surface and provider.** Reuse the injected `AIClientRouter` (it
   handles routing/fallback) unless you need model-specific features (images,
   reasoning level, tools) — then call `LocalModelClient`/`PrivateCloudModelClient`
   directly.
2. **Define structured output** with `@Generable`/`@Guide` if the shape is known;
   otherwise request free text.
3. **Gate it** with `#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)`
   and a runtime `isAvailable` check; for images also check
   `capabilities.contains(.vision)`.
4. **Budget the input** with `TokenBudget` instead of character limits.
5. **Add the persona** to `AppCore/AIPrompts.swift` rather than inlining prompts.
6. **Handle errors** by mapping `LanguageModelError` to user-facing copy and
   degrading gracefully.

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
  Chat/ChatService.swift              # chat orchestration + escalation
  CommandBar/                         # command parsing (local/AI/Claude tiers)
  LessonPlanning/                     # lesson planning service
AppCore/AIPrompts.swift               # all system prompts/personas
Settings/
  AIModelSettingsView.swift           # AIFeatureArea, AIModelOption, picker
  SettingsView.swift                  # Apple Intelligence status rows
Components/
  AppleIntelligenceSheet.swift        # draft generation UI
  AppleIntelligenceSheet+Generation.swift  # on-device/PCC draft routing
  ObservationsView+AI.swift           # observation digests/narrative
  UnifiedNoteEditor/NoteEditorAISuggestion.swift  # tags + photo description
Stories/StoryAnalyzer.swift           # story metadata (text + visual)
Documentation/Architecture/
  AI.md                               # this file
  PrivateCloudCompute.md              # PCC entitlement activation
```
