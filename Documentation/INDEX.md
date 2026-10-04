# Documentation index

Every plan, progress file and reference doc under `Documentation/`, with its status checked against git on 2026-10-04. The convention (index, status line, archive) is in `~/Documents/My Documents/Areas/App Development/README.md` under "Docs in the repos". Built plans live in `Implementation/Archive/`; anything Danny has to do is in Tide (`Areas/App Development/Cosmic Daybook/TODO.md`).

## Cosmic Daybook

The notebook app (macOS, iPad, iPhone).

| File | Kind | Status | Date | What it covers |
|---|---|---|---|---|
| [BUILD_AND_LAUNCH_PERFORMANCE_PLAN.md](Implementation/Archive/BUILD_AND_LAUNCH_PERFORMANCE_PLAN.md) | plan | Built (251ec634) | 2026-09-04 | Build and launch speed: phases 0–4 on main, the rest measured and deferred. |
| [CHECKLIST_REDESIGN_PLAN.md](Implementation/Archive/CHECKLIST_REDESIGN_PLAN.md) | plan | Built (95606c42) | 2026-10-02 | Class checklist grid: mastery marks, cell card, Ready lens. |
| [ENERGY_AND_HEAT_PLAN.md](Implementation/Archive/ENERGY_AND_HEAT_PLAN.md) | plan | Built (e83bace9) | 2026-09-10 | Five phases cutting sync and maintenance heat and battery use. |
| [GROUPS_PAGE_PLAN.md](Implementation/Archive/GROUPS_PAGE_PLAN.md) | plan | Built (158c2bce) | 2026-10-03 | Groups page replacing the Group Planner. |
| [GROUPS_SIM_CHECK_PLAN.md](Implementation/Archive/GROUPS_SIM_CHECK_PLAN.md) | plan | Built (b0c2a6f0) | 2026-10-03 | Simulator check of the Groups page on iPad and iPhone, with three layout fixes. |
| [IPAD_SAMPLE_CLASS_OVERLAP_PLAN.md](Implementation/Archive/IPAD_SAMPLE_CLASS_OVERLAP_PLAN.md) | plan | Built (62682481) | 2026-10-03 | iPad: class and year control no longer covers "Return to My Class". |
| [KEY_VALUE_STORAGE_IMPLEMENTATION.md](Implementation/Archive/KEY_VALUE_STORAGE_IMPLEMENTATION.md) | plan | Built (8483b90e) | 2026-02-23 | iCloud key-value sync of preferences. |
| [POST_PRESENTATION_WORKFLOW.md](Implementation/Archive/POST_PRESENTATION_WORKFLOW.md) | plan | Built (6948166c) | 2026-10-01 | Present a lesson: one sheet, three beats, and its validation checklist. |
| [RECALL_RETENTION.md](Implementation/Archive/RECALL_RETENTION.md) | plan | Built (c946ee20) | 2026-06-25 | Lesson recall and retention checks, v1. |
| [REPOSITORY_ORGANIZATION_PLAN.md](Implementation/Archive/REPOSITORY_ORGANIZATION_PLAN.md) | plan | Built (43d75271) | 2026-07-10 | Incremental repository reorganization log. |
| [SIRI_AI_IMPROVEMENTS.md](Implementation/Archive/SIRI_AI_IMPROVEMENTS.md) | plan | Built (92d0226a) | 2026-06-25 | Siri and Apple Intelligence: nine of ten items; the tenth is the widgets handoff. |
| [STUDENT_WORKSPACE_REDESIGN.md](Implementation/Archive/STUDENT_WORKSPACE_REDESIGN.md) | plan | Built (7431c30c) | 2026-10-01 | Students as a calm workspace: signals, class at a glance, Mac scope bar. |
| [SWIFT_6_2_EVALUATION.md](Implementation/Archive/SWIFT_6_2_EVALUATION.md) | plan | Built (7c79d42c) | 2026-09-03 | Main-actor default isolation adoption. |
| [TODAY_REDESIGN_PLAN.md](Implementation/Archive/TODAY_REDESIGN_PLAN.md) | plan | Built (c2430056) | 2026-10-02 | Today redesign: inspector, Meetings, Gone quiet, linked todos. |
| [design-system-migration.md](Implementation/Archive/design-system-migration.md) | plan | Built (353485ec) | 2026-09-22 | Corner-radius tokens and surface modifiers recipe. |
| [roster-provider-migration.md](Implementation/Archive/roster-provider-migration.md) | plan | Built (8e2f7c04) | 2026-09-21 | `RosterStore` and `LessonCatalog` migration. |
| [MACOS_HIG_PLAN.md](Implementation/MACOS_HIG_PLAN.md) | plan | In progress (phases 0–3 on main) | 2026-09-30 | macOS Human Interface Guidelines conformance; phase 4 and sweeps open. |
| [SCHOOL_YEAR_SEPARATION.md](Implementation/SCHOOL_YEAR_SEPARATION.md) | plan | In progress (paused; phases 0–2 on main) | 2026-09-30 | School-year lens; reports, exports and the activity stamp never built. |
| [DEBUG_NOTEBOOK_PLAN.md](Implementation/DEBUG_NOTEBOOK_PLAN.md) | plan | Not built | 2026-10-04 | Debug builds open a fake, local-only notebook; the real one only via the Real Notebook scheme. |
| [SIRI_WIDGETS_HANDOFF.md](Implementation/SIRI_WIDGETS_HANDOFF.md) | plan | Not built | 2026-09-30 | Widgets and Control Center recipe; no widget target exists. |
| [organization-audits/2026-10-02.md](organization-audits/2026-10-02.md) | review | — | 2026-10-02 | Organization audit of the repo with the changes applied. |
| [ADRs/README.md](ADRs/README.md) | decisions | — | — | Index of the architecture decision records. |
| [ADRs/ADR-001-swiftdata-enum-pattern.md](ADRs/ADR-001-swiftdata-enum-pattern.md) | decisions | Accepted | 2025-11 | Core Data enum raw-value pattern. |
| [ADRs/ADR-003-repository-pattern.md](ADRs/ADR-003-repository-pattern.md) | decisions | Accepted | 2026-01 | When to use repositories versus `@FetchRequest`. |
| [ADRs/ADR-004-dependency-injection.md](ADRs/ADR-004-dependency-injection.md) | decisions | Accepted | 2026-02 | Dependency injection through `AppDependencies`. |
| [Architecture/AI.md](Architecture/AI.md) | other | — | — | How the AI features are built and extended. |
| [Architecture/ALBUMS.md](Architecture/ALBUMS.md) | other | — | — | Teaching-album PDFs: rules and notes. |
| [Architecture/ARCHITECTURE.md](Architecture/ARCHITECTURE.md) | other | — | — | App lifecycle, navigation, layers, concurrency. |
| [Architecture/BACKUP_SYSTEM.md](Architecture/BACKUP_SYSTEM.md) | other | — | — | Backup format, restore, and the rules for changing it. |
| [Architecture/CoreDataLogging.md](Architecture/CoreDataLogging.md) | other | — | — | Silencing Core Data and SQLite debug logging. |
| [Architecture/DATA_MODELS.md](Architecture/DATA_MODELS.md) | other | — | — | Entities, patterns and integrity rules. |
| [Architecture/LESSON_PRESENTATION_WORK_INTEGRATION.md](Architecture/LESSON_PRESENTATION_WORK_INTEGRATION.md) | other | — | — | How lessons, presentations and work connect. |
| [Architecture/MCP_SERVER.md](Architecture/MCP_SERVER.md) | other | — | — | The Claude Desktop MCP server: design, tools, rules. |
| [Architecture/PrivateCloudCompute.md](Architecture/PrivateCloudCompute.md) | other | — | — | Using Apple's server model for long drafts. |
| [Architecture/Work_Models_Best_Practices.md](Architecture/Work_Models_Best_Practices.md) | other | — | — | Best practices for the work models. |
| [Manuals/](Manuals/) | other | — | — | `DeveloperManual.md`, `UserManual.md` and the two PDF generator scripts; PDFs are in `Generated/`. |
| [README.md](README.md) | other | — | — | Folder overview and how to regenerate the manuals. |

## Daybook Assistant

The attendance and Restock app for the assistants. It has no docs of its own under `Daybook Assistant/`; its plans live here.

| File | Kind | Status | Date | What it covers |
|---|---|---|---|---|
| [ASSISTANT_TOP_25_FIXES_PLAN.md](Implementation/Archive/ASSISTANT_TOP_25_FIXES_PLAN.md) | plan | Built (944eb2c5) | 2026-09-29 | 20 fixes to the Daybook Assistant from the top-25 review (moved here from `~/.claude/plans/` on 2026-10-04). |
| [ASSISTANT_BUG_FIX_PLAN.md](Implementation/ASSISTANT_BUG_FIX_PLAN.md) | plan | Not built (planned; waiting on which phases to run before the 2026-10-09 usage reset) | 2026-10-04 | Fixes for the ~50 findings of the 2026-10-04 Daybook Assistant bug hunt, in six phases. |

## Both

Docs that cover the seam between the two apps: shared sync and classroom share, Siri, Restock, build settings, the build board's progress copy and the performance baselines.

| File | Kind | Status | Date | What it covers |
|---|---|---|---|---|
| [LOGIC_BREAK_SWEEP_PLAN.md](Implementation/Archive/LOGIC_BREAK_SWEEP_PLAN.md) | plan | Built (81e8f4cb; loose ends fa1c434f) | 2026-09-30 | Whole-app logic-break sweep and its fix order (moved here from `~/.claude/plans/` on 2026-10-04). |
| [PLAIN_ENGLISH_PLAN.md](Implementation/Archive/PLAIN_ENGLISH_PLAN.md) | plan | Built (9503d7f2) | 2026-10-03 | Every message the apps show says what happened and what to do. |
| [RESTOCK_PLAN.md](Implementation/RESTOCK_PLAN.md) | plan | In progress (phases 1–3 on main, 015c269c) | 2026-10-03 | Restock: supplies and orders as one page, shared with the Assistant; shipped to TestFlight, device checks open. |
| [PROGRESS.md](PROGRESS.md) | progress | In progress (Milestone 13 active) | 2026-10-04 | Repo copy of the build board: Production move, Assistant improvements, logic-break sweep, Plain English. |
| [Implementation/perf-baselines/](Implementation/perf-baselines/) | other | — | 2026-09-04 to 2026-09-29 | Dated performance measurements (16 files): clean build, launch, energy waves, build-speed levers. |
| [Architecture/BUILD_SETTINGS.md](Architecture/BUILD_SETTINGS.md) | other | — | — | Build settings and why. |
| [Architecture/CloudKit/CLOUDKIT_GUIDE.md](Architecture/CloudKit/CLOUDKIT_GUIDE.md) | other | — | — | Sync, sharing, persistent history, and the rules. |
| [Architecture/FEATURE_OWNERSHIP.md](Architecture/FEATURE_OWNERSHIP.md) | other | — | — | Where code belongs by feature. |
| [Architecture/RESTOCK.md](Architecture/RESTOCK.md) | other | — | — | Restock rules (supplies and orders). |
| [Architecture/SIRI.md](Architecture/SIRI.md) | other | — | — | Siri and App Intents: rules and notes. |
