# Cosmic Daybook: start here

The map of this app's documents. The three tables are built by `docs-index` from the
status line at the top of each plan in `Plans/`, so change a plan's status there and
run `docs-index`; edit only the Other documents section by hand.

## Not done yet

| Plan | What it is | Status | Date |
|---|---|---|---|
| [Plan - Add a check-in to existing work](<Plans/Plan - Add a check-in to existing work.md>) | `update_work` gets `add_check_in_on` / `add_check_in_purpose` / `add_check_in_for_this_child_only`, so a check-in can be scheduled on work that already exists. | Working on it | 2026-10-06 |
| [Plan - Daybook Assistant bug fixes](<Plans/Plan - Daybook Assistant bug fixes.md>) | Fixes for the ~50 findings of the 2026-10-04 Daybook Assistant bug hunt, in six phases. | Working on it | 2026-10-05 |
| [Plan - Debug builds open a fake notebook](<Plans/Plan - Debug builds open a fake notebook.md>) | Debug builds open a fake, local-only notebook; the real one only through the Real Notebook scheme. | Not started | 2026-10-04 |
| [Plan - Names you set yourself](<Plans/Plan - Names you set yourself.md>) | A small shared list of each person's current name, set by that person, so the Assistant says "Danny" instead of "your guide" and a rename shows everywhere, old entries included. | Working on it | 2026-10-05 |
| [Plan - Restock](<Plans/Plan - Restock.md>) | Supplies and orders as one page, shared with the Daybook Assistant; shipped to TestFlight, device checks open. | Working on it | 2026-10-03 |
| [Plan - School year separation](<Plans/Plan - School year separation.md>) | A school-year lens across the app; reports, exports and the activity stamp were never built. | Working on it | 2026-09-30 |
| [Plan - Who made a change](<Plans/Plan - Who made a change.md>) | Save each device's real CloudKit ID instead of the shared stand-in, show who added something only when it isn't you, and make the office run a plain errand list (what, how urgent, where it goes). | Working on it | 2026-10-05 |
| [Plan - Widgets and Control Center](<Plans/Plan - Widgets and Control Center.md>) | Widgets and Control Center recipe; no widget target exists yet. | Not started | 2026-09-30 |
| [Plan - macOS Human Interface Guidelines](<Plans/Plan - macOS Human Interface Guidelines.md>) | Making the Mac app follow Apple's Mac design guidelines; phase 4 and sweeps are still open. | Working on it | 2026-09-30 |

## Done

| Plan | What it is | Status | Date |
|---|---|---|---|
| [Plan - Sync and sharing fixes](<Plans/Plan - Sync and sharing fixes.md>) | fix every finding of the 2026-10-05 sync and sharing bug hunt in six parallel agents, add who-changed-it to staple history (schema 17), and land it all on main. | Done (90aedef9) | 2026-10-06 |
| [Plan - Data model and launch repair fixes](<Plans/Plan - Data model and launch repair fixes.md>) | Fix all 64 findings of that hunt, each behavior fix with a regression test, in six agent phases run in two parallel waves, then restore from the error screen, off-main store loading, a review and one squash onto main. | Done (0ab967ff) | 2026-10-06 |
| [Plan - iPad Sample Class banner overlap](<Plans/Plan - iPad Sample Class banner overlap.md>) | iPad: the class and year control no longer covers Return to My Class. | Done (62682481) | 2026-10-03 |
| [Plan - Plain English messages](<Plans/Plan - Plain English messages.md>) | Every message the apps show says what happened and what to do. | Done (9503d7f2) | 2026-10-03 |
| [Plan - Groups page simulator check](<Plans/Plan - Groups page simulator check.md>) | Simulator check of the Groups page on iPad and iPhone, with three layout fixes. | Done (b0c2a6f0) | 2026-10-03 |
| [Plan - Groups page](<Plans/Plan - Groups page.md>) | A Groups page replacing the Group Planner. | Done (158c2bce) | 2026-10-03 |
| [Plan - Today redesign](<Plans/Plan - Today redesign.md>) | Today redesign: inspector, Meetings, Gone quiet, linked todos. | Done (c2430056) | 2026-10-02 |
| [Plan - Class checklist redesign](<Plans/Plan - Class checklist redesign.md>) | Class checklist grid: mastery marks, cell card, Ready lens. | Done (95606c42) | 2026-10-02 |
| [Plan - Students workspace redesign](<Plans/Plan - Students workspace redesign.md>) | Students as a calm workspace: signals, class at a glance, Mac scope bar. | Done (7431c30c) | 2026-10-01 |
| [Plan - Present a lesson](<Plans/Plan - Present a lesson.md>) | Present a lesson: one sheet, three beats, and its validation checklist. | Done (6948166c) | 2026-10-01 |
| [Plan - Logic-break sweep](<Plans/Plan - Logic-break sweep.md>) | Whole-app logic-break sweep and its fix order. | Done (81e8f4cb) | 2026-09-30 |
| [Plan - Daybook Assistant 20 fixes](<Plans/Plan - Daybook Assistant 20 fixes.md>) | Twenty fixes to the Daybook Assistant from the top-25 review. | Done (944eb2c5) | 2026-09-29 |
| [Plan - Design system migration](<Plans/Plan - Design system migration.md>) | Corner-radius tokens and surface modifiers recipe. | Done (353485ec) | 2026-09-22 |
| [Plan - Roster and lesson catalog migration](<Plans/Plan - Roster and lesson catalog migration.md>) | The roster and lesson-catalog stores replace per-view student fetches. | Done (8e2f7c04) | 2026-09-21 |
| [Plan - Energy and heat](<Plans/Plan - Energy and heat.md>) | Five phases cutting sync and maintenance heat and battery use. | Done (e83bace9) | 2026-09-10 |
| [Plan - Build and launch speed](<Plans/Plan - Build and launch speed.md>) | Build and launch speed: phases 0-4 on main, the rest measured and deferred. | Done (251ec634) | 2026-09-04 |
| [Plan - Swift 6.2 main-actor default](<Plans/Plan - Swift 6.2 main-actor default.md>) | Adopting main-actor default isolation. | Done (7c79d42c) | 2026-09-03 |
| [Plan - Repository organization](<Plans/Plan - Repository organization.md>) | Incremental repository reorganization log. | Done (43d75271) | 2026-07-10 |
| [Plan - Siri and Apple Intelligence](<Plans/Plan - Siri and Apple Intelligence.md>) | Siri and Apple Intelligence: nine of ten items; the tenth is the widgets plan. | Done (92d0226a) | 2026-06-25 |
| [Plan - Lesson recall and retention](<Plans/Plan - Lesson recall and retention.md>) | Lesson recall and retention checks, first version. | Done (c946ee20) | 2026-06-25 |
| [Plan - iCloud preference sync](<Plans/Plan - iCloud preference sync.md>) | Preferences sync across devices through iCloud key-value storage. | Done (8483b90e) | 2026-02-23 |

## Won't do

None.

## Other documents

<!-- other-documents:start -->
Cosmic Daybook (the notebook app for macOS, iPad and iPhone) and the Daybook Assistant (the attendance and Restock app for the assistants) share this repo and these docs. The Daybook Assistant has no docs of its own under `Daybook Assistant/`; its plans live in Plans. Anything Danny has to do is in Tide (`~/Documents/My Documents/Areas/App Development/Cosmic Daybook/TODO.md` and `~/Documents/My Documents/Areas/App Development/Daybook Assistant/TODO.md`). Old paths are listed in [Old names](<Old names.md>).

### Which app each plan is for

- **Cosmic Daybook:** every plan not listed in the next two lines.
- **Daybook Assistant:** [Daybook Assistant 20 fixes](<Plans/Plan - Daybook Assistant 20 fixes.md>) and [Daybook Assistant bug fixes](<Plans/Plan - Daybook Assistant bug fixes.md>).
- **Both apps:** [Logic-break sweep](<Plans/Plan - Logic-break sweep.md>), [Plain English messages](<Plans/Plan - Plain English messages.md>) and [Restock](<Plans/Plan - Restock.md>).

### Documents

- [Progress](<Progress.md>): the repo copy of the build board (Production move, Assistant improvements, logic-break sweep, Plain English). Covers both apps.
- [Technical notes](<Technical notes/>): how the app is built and the rules for changing it.
  - [ARCHITECTURE](<Technical notes/ARCHITECTURE.md>): app lifecycle, navigation, layers, concurrency.
  - [DATA_MODELS](<Technical notes/DATA_MODELS.md>): entities, patterns and integrity rules.
  - [AI](<Technical notes/AI.md>): how the AI features are built and extended.
  - [ALBUMS](<Technical notes/ALBUMS.md>): teaching-album PDFs, rules and notes.
  - [BACKUP_SYSTEM](<Technical notes/BACKUP_SYSTEM.md>): backup format, restore, and the rules for changing it.
  - [CoreDataLogging](<Technical notes/CoreDataLogging.md>): silencing Core Data and SQLite debug logging.
  - [LESSON_PRESENTATION_WORK_INTEGRATION](<Technical notes/LESSON_PRESENTATION_WORK_INTEGRATION.md>): how lessons, presentations and work connect.
  - [MCP_SERVER](<Technical notes/MCP_SERVER.md>): the Claude Desktop MCP server: design, tools, rules.
  - [PrivateCloudCompute](<Technical notes/PrivateCloudCompute.md>): using Apple's server model for long drafts.
  - [Work_Models_Best_Practices](<Technical notes/Work_Models_Best_Practices.md>): best practices for the work models.
  - Shared with the Daybook Assistant: [BUILD_SETTINGS](<Technical notes/BUILD_SETTINGS.md>) (build settings and why), [CLOUDKIT_GUIDE](<Technical notes/CloudKit/CLOUDKIT_GUIDE.md>) (sync, sharing, persistent history, and the rules), [FEATURE_OWNERSHIP](<Technical notes/FEATURE_OWNERSHIP.md>) (where code belongs by feature), [RESTOCK](<Technical notes/RESTOCK.md>) (supplies and orders rules) and [SIRI](<Technical notes/SIRI.md>) (Siri and App Intents: rules and notes).
- [Decision records](<Technical notes/Decision records/README.md>): the architecture decision records.
  - [ADR-001](<Technical notes/Decision records/ADR-001-swiftdata-enum-pattern.md>): Core Data enum raw-value pattern (accepted 2025-11).
  - [ADR-003](<Technical notes/Decision records/ADR-003-repository-pattern.md>): when to use repositories versus `@FetchRequest` (accepted 2026-01).
  - [ADR-004](<Technical notes/Decision records/ADR-004-dependency-injection.md>): dependency injection through `AppDependencies` (accepted 2026-02).
- [Performance baselines](<Technical notes/Performance baselines/>): 16 dated performance measurements (2026-09-04 to 2026-09-29): clean build, launch, energy waves, build-speed levers. Covers both apps.
- [Reviews](<Reviews/>): [2026-10-02](<Reviews/Organization audit 2026-10-02.md>) is the organization audit of the repo with the changes applied; [2026-10-05](<Reviews/Sync and sharing bug hunt 2026-10-05.md>) is the sync and sharing bug hunt (findings only, nothing fixed yet).

### Manuals (these stay in `Documentation/`)

Project documentation lives outside the synchronized Xcode source folders so it is not compiled or copied into the app bundle. Two Python scripts read the manuals beside them, so `Documentation/` keeps only these two folders.

- [Manuals](<../Documentation/Manuals/>): `DeveloperManual.md`, `UserManual.md` and the two PDF generator scripts (`generate_pdf.py`, `generate_user_pdf.py`).
- [Generated](<../Documentation/Generated/>): the generated PDF manuals.

Regenerate the manuals from the repository root. Each script reads its Markdown source from `Manuals/` and writes the PDF to `Generated/`.

```bash
python3 Documentation/Manuals/generate_pdf.py
python3 Documentation/Manuals/generate_user_pdf.py
```

Check the repository structure after moving files or changing folders. It checks that the completed organization remains intact without compiling the app.

```bash
Scripts/check_repository_structure.sh
```
### Notes carried over from the old Documentation index and README

These lines came from the old Documentation index and README, which this page replaces.

#### Documentation index

Every plan, progress file and reference doc under `docs/`, with its status checked against git on 2026-10-04. The convention (index, status line, archive) is in `~/Documents/My Documents/Areas/App Development/README.md` under "Docs in the repos". Built plans live in `docs/Plans/`; anything Danny has to do is in Tide (`~/Documents/My Documents/Areas/App Development/Cosmic Daybook/TODO.md`).

##### Cosmic Daybook

The notebook app (macOS, iPad, iPhone).

##### Daybook Assistant

The attendance and Restock app for the assistants. It has no docs of its own under `Daybook Assistant/`; its plans live here.

##### Both

Docs that cover the seam between the two apps: shared sync and classroom share, Siri, Restock, build settings, the build board's progress copy and the performance baselines.

#### Documentation

Project documentation lives outside the synchronized Xcode source folders so it is not compiled or copied into the app bundle.

##### Contents

Start at [INDEX.md](<Start here.md>): every plan and progress file with its status, date and where it lives.

- `Architecture/` - system design, data model, CloudKit, AI, backup, albums, Siri, build settings, ownership conventions, and technical reference material (including the detailed feature notes that used to live in `Cosmic Daybook/CLAUDE.md`). Now `docs/Technical notes/`.
- `ADRs/` - architecture decision records. Now `docs/Technical notes/Decision records/`.
- `Implementation/` - active implementation plans and handoffs; finished plans move to `Plans/`. Each plan opens with a status line, and `Start here.md` lists them all. Now `docs/Plans/`, where plans never move.
- `Manuals/` - Markdown sources and PDF generation scripts for the developer and user manuals.
- `Generated/` - generated PDF manuals.

##### Regenerating manuals

Run either generator from the repository root:

##### Checking repository structure

Run the lightweight structure check from the repository root after moving files or changing folders:
<!-- other-documents:end -->
