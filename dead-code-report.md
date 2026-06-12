# Dead-code analysis — Maria's Notebook

Date: 2026-06-10. Tree state: mid-refactor working tree (uncommitted module deletions), builds cleanly.

> **Status update (2026-06-10, final):** Sections **1–4 and 6 are executed**, plus the re-scan's second wave (14 files) and third wave (1 file). The 3 multi-line constants originally skipped are now removed too, along with the helper types that existed only for them (`EntityChange`, `EntitySchemaChanges`, `PayloadField`, `ParshaTopicEntry`). One deliberate exception: **`WorkDTO` in Backup/BackupTypes+Work.swift is kept** — it is unreferenced, but carries an explicit "retained for backward compatibility with older backup files" comment; nothing can decode it today, so either the comment is stale (delete it) or legacy work-restore is broken (investigate) — Danny's call. The 3 legacy `*_Previews` structs (section 6) were also left, as previously noted harmless. **Section 5 (uncalled methods) is the only section still open.**
Method: whole-repo token index (1,142 app + 18 test Swift files, comments stripped, string literals kept as references; pbxproj/plists/xcdatamodel counted as reference sources), Swift-aware exclusions (`@main`, AppIntents, Core Data `CD*` classes, SDK delegate witnesses, preview providers), then per-candidate adversarial verification of every dead-file claim plus precision sampling of the symbol categories.
Definition used: a file/symbol is *dead* when nothing outside its own file references it (a `#Preview` inside the same file does not count).

## 1. Dead files — DELETED 2026-06-10 (99 files, ~11,163 LOC)

Every symbol these files declare (types and extension members) was verified unreferenced anywhere else, including string-literal and non-Swift references.

**Maria's Notebook/Agenda/**
- `AgendaScaffoldingViews.swift` (92 LOC) — DayHeaderView, AgendaView

**Maria's Notebook/AppCore/**
- `AppSchema.swift` (16 LOC) — AppSchema
- `CacheCoordinator.swift` (445 LOC) — CacheCoordinator, Caching, CacheInvalidationEvent, CacheMetrics, ReactiveCache, CacheDebugView, CacheMetricRow
- `MainToolbar.swift` (45 LOC) — MainToolbar
- `PreferenceRegistry.swift` (97 LOC) — PreferenceType, PreferenceDefinition, PreferenceRegistry

**Maria's Notebook/AppCore/RootView/**
- `QuickNewPresentationSheet.swift` (358 LOC) — QuickNewPresentationSheet

**Maria's Notebook/AppCore/TodayView/**
- `TodayViewSheets.swift` (112 LOC) — applySheets

**Maria's Notebook/Backup/**
- `BackupStatusView.swift` (202 LOC) — BackupStatusView
- `BackupUI.swift` (24 LOC) — BackupProgressView

**Maria's Notebook/Components/**
- `DatabaseStatsStrip.swift` (78 LOC) — MTSummaryStat, MTSummaryStrip
- `InspectorWrapper.swift` (40 LOC) — InspectorModifier
- `InteractiveCard.swift` (51 LOC) — InteractiveCard
- `LifecycleIndicatorView.swift` (54 LOC) — LifecycleIndicatorView
- `LinkedLessonSection.swift` (125 LOC) — LinkedLessonSection
- `LinkedWorkSection.swift` (67 LOC) — LinkedWorkSection
- `NextLessonsListView.swift` (56 LOC) — NextLessonsListView
- `NotesSection.swift` (18 LOC) — NotesSection
- `NotesSectionView.swift` (41 LOC) — NotesSectionView
- `OpenWorkListView.swift` (170 LOC) — OpenWorkListView
- `PerStudentCompletionList.swift` (67 LOC) — StudentLite, PerStudentCompletionList
- `QuickBannerView.swift` (20 LOC) — QuickBannerView
- `QuickLookPreview.swift` (28 LOC) — PagesOpener
- `ScheduleCheckInSection.swift` (29 LOC) — ScheduleCheckInSection
- `ScheduledCheckInsListSection.swift` (57 LOC) — ScheduledCheckInsListSection
- `SyncStatusBadge.swift` (119 LOC) — SyncStatusBadge, SyncStatusPopover
- `TodoDetailView.swift` (436 LOC) — TodoDetailView
- `ViewModifiers.swift` (41 LOC) — errorMessageStyle, loadingStyle, sectionHeaderStyle

**Maria's Notebook/Components/Checklist/**
- `ChecklistDragSelectionManager.swift` (85 LOC) — ChecklistDragSelectionManager

**Maria's Notebook/Components/Modifiers/**
- `ChipModifier.swift` (70 LOC) — ChipModifier
- `ConditionalDisabledModifier.swift` (43 LOC) — ConditionalDisabledModifier
- `JiggleModifier.swift` (70 LOC) — JiggleModifier
- `ListRowStyleModifier.swift` (52 LOC) — ListRowStyleModifier
- `SubtleCardModifier.swift` (52 LOC) — SubtleCardModifier

**Maria's Notebook/Components/Shared/**
- `BadgeView.swift` (83 LOC) — BadgeView
- `IconPill.swift` (34 LOC) — IconPill
- `LabeledPicker.swift` (46 LOC) — LabeledPicker
- `LabeledTextField.swift` (42 LOC) — LabeledTextField
- `SkeletonView.swift` (105 LOC) — ShimmerModifier, SkeletonBlock, SkeletonRow, SkeletonCard, SkeletonListLoading
- `ToggleRow.swift` (48 LOC) — ToggleRow

**Maria's Notebook/Lessons/**
- `GlobalAttachmentImportHandler.swift` (193 LOC) — GlobalAttachmentImportHandler, GlobalAttachmentImportModifier, QuickAttachmentImportButton, AttachmentDropDelegate
- `IntroductionCard.swift` (230 LOC) — IntroductionCard
- `LessonCardContainer.swift` (100 LOC) — LessonBrowseCard
- `LessonCompactRow.swift` (81 LOC) — LessonCompactRow
- `LessonImportPreviewView.swift` (302 LOC) — LessonImportPreviewView
- `LessonProgressListView.swift` (353 LOC) — LessonProgressListView
- `LessonProgressSection.swift` (548 LOC) — LessonProgressSection
- `LessonsImportCoordinator.swift` (55 LOC) — LessonsImportCoordinator
- `LessonsListView.swift` (88 LOC) — LessonsListView
- `LessonsReorderService.swift` (79 LOC) — LessonsReorderService
- `RightClickCatcher.swift` (48 LOC) — RightClickCatcher, RightClickView
- `SequenceIntroductionSheet.swift` (179 LOC) — SequenceIntroductionSheet
- `SequenceListView.swift` (123 LOC) — SequenceListView

**Maria's Notebook/Logs/**
- `LogsView.swift` (21 LOC) — LogsView

**Maria's Notebook/Models/**
- `PresentationStudentEntry.swift` (18 LOC) — PresentationStudentEntry

**Maria's Notebook/ObservationMode/**
- `ObservationPromptCard.swift` (67 LOC) — ObservationPromptCard
- `ObservationTimerView.swift` (43 LOC) — ObservationTimerView

**Maria's Notebook/Planning/**
- `PlanningDND.swift` (30 LOC) — PlanningDragItem
- `PlanningWeekView.swift` (21 LOC) — PlanningWeekView

**Maria's Notebook/Presentations/**
- `PresentationsSortMode.swift` (9 LOC) — PresentationsSortMode

**Maria's Notebook/Projects/**
- `ProjectTemplateModels.swift` (32 LOC) — JSONStringList
- `ProjectWeeksEditorView.swift` (78 LOC) — InlineLessonPickerSheet

**Maria's Notebook/Services/**
- `BatchOperationService.swift` (134 LOC) — BatchOperationService
- `CurriculumIntroductionStore.swift` (220 LOC) — CurriculumIntroductionStore
- `FollowUpWorkService.swift` (351 LOC) — FollowUpWorkService, PresentationFollowUp, FollowUpAction, FollowUpPriority, WorkSuggestion
- `InboxDataLoader.swift` (154 LOC) — InboxDataLoader, InboxData
- `LessonAnalyticsService.swift` (113 LOC) — LessonAnalyticsService
- `TodoLocationService.swift` (161 LOC) — TodoLocationService
- `WorkConsolidationService.swift` (225 LOC) — WorkConsolidationService

**Maria's Notebook/Settings/**
- `OllamaSettingsModelCatalogSection.swift` (207 LOC) — OllamaSettingsModelCatalogSection
- `SettingsView+AttendanceEmail.swift` (9 LOC) — AttendanceEmailSettingsSection

**Maria's Notebook/Students/**
- `ImportTrackFromLessonsSheet.swift` (215 LOC) — ImportTrackFromLessonsSheet
- `ObservationHeatmapView.swift` (310 LOC) — ObservationHeatmapView, StudentObservation, ObservationStatus, StudentObservationCard
- `PresentationDetailSections.swift` (287 LOC) — PresentationSummarySection, PresentationScheduleSection, PresentationPresentedSection, PresentationNextLessonSection, PresentationFlagsSection, PresentationFollowUpSection, PresentationNotesSection
- `StudentInfoRowsView.swift` (43 LOC) — StudentInfoRowsView
- `StudentsFilterService.swift` (133 LOC) — StudentsFilterService
- `TrackDetailView.swift` (201 LOC) — TrackDetailView
- `TrackListView.swift` (131 LOC) — TrackListView
- `WorkPrintButton.swift` (32 LOC) — WorkPrintButton

**Maria's Notebook/Students/LessonDetail/**
- `PresentationAssignmentService.swift` (154 LOC) — PresentationAssignmentService

**Maria's Notebook/Students/Meetings/**
- `MeetingDetailPopover.swift` (50 LOC) — MeetingDetailPopover

**Maria's Notebook/Utils/**
- `AppKitSceneActivationShim.swift` (23 LOC) — UISceneSession, UIScene
- `ArrayFiltering.swift` (62 LOC) — ArrayFiltering
- `AsyncErrorHandling.swift` (69 LOC) — AsyncErrorHandling
- `DocxTemplateMerger.swift` (92 LOC) — DocxTemplateMerger
- `OptionalBindingHelpers.swift` (62 LOC) — OptionalBindingHelpers
- `PredicateHelpers.swift` (28 LOC) — PredicateHelpers
- `PresentationResolver.swift` (85 LOC) — PresentationResolver
- `StateInitialization.swift` (85 LOC) — StateInitialization, OptionalStateFromDefaults
- `TypeAliases.swift` (25 LOC) — VoidCallback, StudentCallback, LessonCallback, UUIDCallback, StringCallback, BoolCallback, DateCallback

**Maria's Notebook/Work/**
- `PracticePartnershipsView.swift` (455 LOC) — PracticePartnershipsView, PracticePartnershipsSheet, PracticePartnershipsSummaryCard
- `PracticeSessionsListView.swift` (420 LOC) — PracticeSessionsListView
- `ScheduleCheckInSheet.swift` (39 LOC) — ScheduleCheckInSheet
- `WorkCheckInNoteEditor.swift` (82 LOC) — WorkCheckInNoteEditor
- `WorkCompletionBackfill.swift` (54 LOC) — WorkCompletionBackfill
- `WorkDetailBottomBar.swift` (33 LOC) — WorkDetailBottomBar
- `WorkFilters.swift` (25 LOC) — WorkFilters
- `WorkTypePickerSection.swift` (18 LOC) — WorkTypePickerSection
- `WorksAgendaSettings.swift` (23 LOC) — WorksAgendaPrefs, WorksAgendaSettingsView
- `WorksInboxOrderStore.swift` (37 LOC) — WorksInboxOrderStore

Note: `Components/DragPayload.swift:6` has a doc comment referencing `PlanningDragItem` — update it when deleting `Planning/PlanningDND.swift`.

## 2. Vestigial in-app test code — DELETED 2026-06-10

These compile into the **shipping app binary** (the synchronized-groups project only excludes Info.plist/README.md):
- `Maria's Notebook/Tests/` — 8 files of Swift Testing migration-phase suites (Phase4–Phase7). Runtime-discoverable only under a test plan, and the assertions are stale baselines (e.g. Phase7 asserts backup format v12 / 55 registry entries; current is v17 / more entities) — they would fail if ever run. Delete, or move the still-relevant ones into the `Maria's Notebook Tests` target.
- `Backup/BackupRestorePreviewTests.swift` (~350 LOC) — same situation.

## 3. Orphan types inside otherwise-live files (44)

Declared and never used — not even in their own file. Deleting them is a targeted edit, not a file deletion. Notable: `MCPClient`/`MockMCPClient` (superseded by `AnthropicAPIClient`/`OllamaClient`/`LocalModelClient`/`AIClientRouter`) and `WorksPlanningViewModel` (entire @Observable class).

- `struct AgendaShellView` — Maria's Notebook/Agenda/AgendaComponents.swift:3
- `struct AgendaWeekHeaderView` — Maria's Notebook/Agenda/AgendaComponents.swift:93
- `struct AgendaDayStripView` — Maria's Notebook/Agenda/AgendaComponents.swift:165
- `struct AgendaDaySectionHeaderView` — Maria's Notebook/Agenda/AgendaComponents.swift:187
- `struct AgendaPeriodChipView` — Maria's Notebook/Agenda/AgendaComponents.swift:216
- `enum PreviewEnvironment` — Maria's Notebook/AppCore/PreviewEnvironment.swift:22
- `struct KeyboardShortcutsTip` — Maria's Notebook/AppCore/Tips/AppTips.swift:42
- `struct WorkDTO` — Maria's Notebook/Backup/BackupTypes+Work.swift:11
- `struct BackupSummary` — Maria's Notebook/Backup/BackupTypes.swift:253
- `struct BackupDocument` — Maria's Notebook/Backup/Core/BackupDocuments.swift:5
- `struct LoadMoreTrigger` — Maria's Notebook/Components/PaginatedList.swift:102
- `struct StudentFilterChip` — Maria's Notebook/Components/StudentSharedComponents.swift:282
- `struct AreaGrainLabel` — Maria's Notebook/Components/SubjectGrainPill.swift:361
- `struct StudentsSection` — Maria's Notebook/Lessons/LessonPickerComponents.swift:151
- `struct StatusSection` — Maria's Notebook/Lessons/LessonPickerComponents.swift:245
- `struct KeyboardShortcutsOverlay` — Maria's Notebook/Lessons/LessonPickerComponents.swift:292
- `enum CommunicationTab` — Maria's Notebook/Models/CommunicationType.swift:50
- `typealias PresentationState` — Maria's Notebook/Models/Presentation.swift:46
- `struct ObservationPatternsDashboard` — Maria's Notebook/ObservationMode/ObservationPatternsDashboard.swift:9
- `enum ObservationPromptLibrary` — Maria's Notebook/ObservationMode/ObservationPrompts.swift:14
- `struct DayKey` — Maria's Notebook/Planning/PlanningModels.swift:30
- `struct ProcedureCompactRow` — Maria's Notebook/Procedures/ProcedureRow.swift:60
- `struct LocalJSONStringList` — Maria's Notebook/Projects/ProjectModels.swift:29
- `enum LifecycleError` — Maria's Notebook/Services/LifecycleService.swift:6
- `class MCPClient` — Maria's Notebook/Services/MCPClient.swift:177
- `class MockMCPClient` — Maria's Notebook/Services/MCPClient.swift:270
- `struct AvailableTrack` — Maria's Notebook/Services/SequenceTrackService.swift:5
- `protocol LifecycleAwareService` — Maria's Notebook/Services/ServiceProtocols.swift:26
- `struct SettingsToggleRow` — Maria's Notebook/Settings/SettingsComponents.swift:196
- `struct TemplateCard` — Maria's Notebook/Settings/SettingsComponents.swift:226
- `struct OverviewStatsGrid` — Maria's Notebook/Settings/SettingsComponents.swift:313
- `struct StudentSelectionRow` — Maria's Notebook/Students/PresentationDetailComponents.swift:36
- `struct PlannedLessonBanner` — Maria's Notebook/Students/PresentationDetailComponents.swift:173
- `struct SaveErrorAlert` — Maria's Notebook/Students/StudentsViewModifiers.swift:6
- `enum PrintUtils` — Maria's Notebook/Utils/PrintUtils.swift:13
- `enum ValidationHelpers` — Maria's Notebook/Utils/ValidationHelpers.swift:5
- `struct QuickSequencePracticeButton` — Maria's Notebook/Work/GroupPracticeHelper.swift:53
- `enum WorkAgingDebug` — Maria's Notebook/Work/WorkAging.swift:280
- `struct WorkCheckInSummary` — Maria's Notebook/Work/WorkCheckInBadge.swift:28
- `class CDWorkCheckInServiceImpl` — Maria's Notebook/Work/WorkCheckInServiceProtocol.swift:65
- `class MockWorkCheckInService` — Maria's Notebook/Work/WorkCheckInServiceProtocol.swift:119
- `struct WorkPlanItemRow` — Maria's Notebook/Work/WorkDetailViewComponents.swift:66
- `class MockWorkStepService` — Maria's Notebook/Work/WorkStepServiceProtocol.swift:95
- `class WorksPlanningViewModel` — Maria's Notebook/Work/WorksPlanningViewModel.swift:8

A further **151 types** are referenced only within their own file (internal plumbing). They are not independently deletable and most are fine as-is; full list in `/tmp/deadcode_results.json` (`dead_types` entries with `own_refs > 0`).

## 4. Unused constants (155 `static let`)

**Maria's Notebook/AppCore/Constants/SFSymbols.swift** (82):
  `chevronBackward`:13, `chevronForward`:14, `minusCircle`:23, `minusCircleFill`:24, `xmarkCircle`:26, `trashFill`:32, `docFill`:40, `docTextFill`:42, `archiveboxFill`:49, `trayFill`:51, `envelopeFill`:57, `envelopeOpen`:58, `envelopeOpenFill`:59, `messageFill`:61, `phoneFill`:63, `bubbleFill`:65, `bubbleLeft`:66, `bubbleLeftFill`:67, `clockFill`:75, `personCircle`:85, `personCircleFill`:86, `person2Fill`:88, `booksFill`:100, `graduationcapFill`:102, `pencilCircleFill`:105, `backpackFill`:109, `circleInsetFilled`:116, `dotCircle`:117, `dotCircleFill`:118, `exclamationmarkTriangle`:120, `questionmarkCircle`:123, `questionmarkCircleFill`:124, `infoCircleFill`:127, `photoFill`:133, `cameraFill`:135, `videoFill`:137, `playFill`:139, `pauseFill`:141, `micFill`:143, `magnifyingglassCircle`:149, `lineHorizontal3Decrease`:150, `gearshapeFill`:159, `sliderHorizontal3`:160, `switch2`:161, `listDash`:168, `listNumber`:169, `listStar`:170, `listBulletIndent`:171, `checklistChecked`:173, `squareGrid3x3`:175, `upCircle`:184, `downCircle`:185, `downCircleFill`:187, `triangleUp`:188, `triangleDown`:189, `triangleUpFill`:190, `triangleDownFill`:191, `squareFill`:197, `rectangleFill`:199, `capsuleFill`:203, `icloudFill`:213, `icloudAndArrowDown`:214, `icloudAndArrowUp`:215, `externaldriveFill`:217, `mappinCircle`:225, `mappinCircleFill`:226, `locationFill`:228, `houseFill`:230, `starLeading`:237, `flagFill`:241, `pencilTip`:248, `pencilTipCrop`:249, `paintbrushFill`:253, `textAlignCenter`:265, `textAlignRight`:266, `sunFill`:285, `moonFill`:287, `cloudFill`:289, `chartBar`:295, `chartBarFill`:296, `chartPie`:297, `chartPieFill`:298

**Maria's Notebook/AppCore/Constants/UIConstants.swift** (31):
  `dayHeaderApproxHeight`:14, `labelHeight`:15, `dropZoneCornerRadius`:18, `dropZoneStrokeDash`:19, `planningWindowDays`:27, `iconSizeXLarge`:161, `xxLarge`:181, `triple`:212, `quad`:215, `modal`:232, `topmost`:235, `instant`:243, `veryFast`:246, `slow`:261, `smooth`:275, `interactive`:278, `veryShort`:289, `shortMessage`:310, `recentDays`:321, `monthDays`:322, `quarterDays`:323, `yearDays`:324, `twoYearDays`:325, `smallBatch`:328, `mediumBatch`:329, `largeBatch`:330, `maxBackupRetention`:333, `maxStepperValue`:334, `maxWarningDays`:335, `dashedTight`:346, `dashedSmall`:349

**Maria's Notebook/AppCore/Constants/UserDefaultsKeys.swift** (13):
  `backupEncryptDefault`:25, `autoBackupLastScheduledDate`:33, `incrementalBackupLastDate`:36, `incrementalBackupLastID`:37, `backupIntegrityAutoVerifyEnabled`:40, `backupIntegrityWarningDaysThreshold`:41, `backupNotificationsEnabled`:44, `backupNotificationsShowSuccess`:45, `backupNotificationsShowFailure`:46, `backupNotificationsShowHealthWarnings`:47, `reminderSyncSyncListName`:74, `whatsNewDismissedVersion`:149, `backupAgeWarningDays`:150

**Maria's Notebook/AppCore/Constants/BackupConstants.swift** (7):
  `streamingBatchSize`:8, `deltaChunkSize`:11, `deltaCompressionThreshold`:15, `simultaneousModificationThreshold`:21, `entityDiffThreshold`:25, `telemetrySuccessThreshold`:33, `telemetryWarningThreshold`:36

**Maria's Notebook/Backup/Core/BackupMigrationManifest.swift** (7):
  `minimumSupportedVersion`:168, `studentChanges`:272, `lessonChanges`:282, `noteChanges`:293, `projectChanges`:303, `attendanceChanges`:341, `payloadFields`:364

**Maria's Notebook/AppCore/Constants/FormattingConstants.swift** (3):
  `noDecimal`:20, `fourDigitYear`:25, `twoDigitMonth`:28

**Maria's Notebook/Presentations/UnifiedPresentationWorkflowPanelComponents.swift** (3):
  `workflowToggle`:97, `workflowBody`:105, `workflowBodyMedium`:106

**Maria's Notebook/AppCore/Theme.swift** (2):
  `elevated`:198, `wideUppercase`:297

**Maria's Notebook/AppCore/AppTheme+Spacing.swift** (1):
  `cardPadding`:65

**Maria's Notebook/AppCore/Constants/BatchingConstants.swift** (1):
  `largeDatasetThreshold`:9

**Maria's Notebook/AppCore/PreferenceRegistry.swift** (1):
  `knownPrefixes`:84

**Maria's Notebook/ObservationMode/MontessoriObservationTags.swift** (1):
  `normalizationIndicators`:60

**Maria's Notebook/Planning/PlanningDND.swift** (1):
  `planningDragItem`:7

**Maria's Notebook/Services/ParshaMetadataService.swift** (1):
  `allTopicsIndexed`:81

**Maria's Notebook/Work/WorkScheduleDateLogic.swift** (1):
  `primaryLabel`:35

Caveat for `UserDefaultsKeys`: this verifies the Swift *constant* is unreferenced. If a preference was ever written on users' devices, the stored value simply becomes orphaned data — harmless.

## 5. Uncalled methods — EXECUTED 2026-06-11 (201 deleted, 12 system-invoked kept)

Every method below has zero references repo-wide. Each was examined in context by a verification agent (containing type's protocol conformances checked, including extension conformances).

### Keep — system-invoked (12)

- `applicationWillTerminate` — Maria's Notebook/AppCore/AutoBackupAppDelegate.swift:25 — App delegate — quit-time auto-backup hook
- `mailComposeController` — Maria's Notebook/Attendance/AttendanceEmail.swift:385 — MFMailComposeViewControllerDelegate — mail sheet callback
- `imagePickerController` — Maria's Notebook/Components/QuickNote/QuickNoteComponents+Chips.swift:63 — UIImagePickerControllerDelegate — photo picker callback
- `imagePickerControllerDidCancel` — Maria's Notebook/Components/QuickNote/QuickNoteComponents+Chips.swift:72 — UIImagePickerControllerDelegate — photo picker callback
- `numberOfPreviewItems` — Maria's Notebook/Components/TodoEditSheet.swift:262 — QLPreviewControllerDataSource — attachment preview callback
- `previewController` — Maria's Notebook/Components/TodoEditSheet.swift:263 — QLPreviewControllerDataSource — attachment preview callback
- `textViewDidChange` — Maria's Notebook/Components/UnifiedNoteEditor/SmartTextEditor.swift:47 — UITextViewDelegate — iOS text editor callback
- `textDidChange` — Maria's Notebook/Components/UnifiedNoteEditor/SmartTextEditor.swift:142 — NSTextViewDelegate — macOS text editor callback
- `cloudSharingController` — Maria's Notebook/Sharing/CloudSharingControllerWrapper.swift:47 — UICloudSharingControllerDelegate — share sheet callback
- `itemTitle` — Maria's Notebook/Sharing/CloudSharingControllerWrapper.swift:54 — UICloudSharingControllerDelegate — share sheet callback
- `cloudSharingControllerDidSaveShare` — Maria's Notebook/Sharing/CloudSharingControllerWrapper.swift:58 — UICloudSharingControllerDelegate — share sheet callback
- `cloudSharingControllerDidStopSharing` — Maria's Notebook/Sharing/CloudSharingControllerWrapper.swift:64 — UICloudSharingControllerDelegate — share sheet callback

### Deleted (201)

Notable subgroups worth a deliberate glance: the repository layer loses unused CRUD surface (ProjectRepository 7, PresentationRepository 6, ReminderRepository 4, MeetingRepository 3 — delete unless you want the symmetric API kept for upcoming features); `AIReportService.generateNarrative`/`gatherReportData` mean the AI report feature is currently UNREACHABLE from any UI; `BackupTransactionManager.rollbackToActiveCheckpoint` is a manual-rollback API the automatic rollback path does not use; Theme+ViewModifiers loses 18 unused styling helpers.

- Maria's Notebook/Agenda/AgendaComponents.swift — `movedStart`:11
- Maria's Notebook/AppCore/AppDependencies.swift — `preloadPresentationsData`:342
- Maria's Notebook/AppCore/AppRouter.swift — `requestOpenAttendance`:141, `requestQuickActions`:156, `navigateToTab`:178, `setStudentsMode`:183, `clearPlanLessonRequest`:198
- Maria's Notebook/AppCore/CloudKitConfiguration.swift — `getCloudKitContainerID`:17
- Maria's Notebook/AppCore/CloudKitConfigurationService.swift — `clearErrorLog`:237, `getErrorSummary`:242, `markActive`:257, `markInactive`:264
- Maria's Notebook/AppCore/CoreDataStack.swift — `fetchSharesInSharedStore`:431, `acceptShareInvitation`:437
- Maria's Notebook/AppCore/DatabaseInitializationService.swift — `handleCriticalDatabaseInitError`:91
- Maria's Notebook/AppCore/Theme+ViewModifiers.swift — `displayTracking`:26, `overlineStyle`:31, `badgeTracking`:40, `pageTitleStyle`:54, `majorSectionHeaderStyle`:61, `rowTitleStyle`:67, `rowSubtitleStyle`:74, `metadataStyle`:81, `chartHighlightStyle`:91, `chartDimmedStyle`:99, `denseGridStyle`:107, `tabularNumberStyle`:114, `formLabelStyle`:126, `formValueStyle`:133, `mutedHeavyStyle`:141, `deemphasizedStyle`:149, `fontHierarchy`:182, `shifted`:190
- Maria's Notebook/AppCore/TodayView/TodayViewHelpers.swift — `updateAttendanceStatus`:157
- Maria's Notebook/Attendance/AttendanceEmail.swift — `mailtoURLForCurrentPrefs`:138, `sendOrFallbackUsingMailAppForCurrentPrefs`:249
- Maria's Notebook/Attendance/AttendanceLookup.swift — `attendanceStatus`:10
- Maria's Notebook/Backup/BackupService+DataCollection.swift — `safeFetchInBatches`:282
- Maria's Notebook/Backup/BackupService.swift — `estimateBackupSizeFromCounts`:31
- Maria's Notebook/Backup/BackupServiceHelpers.swift — `filterByStudents`:169, `filterByDateRange`:178, `filterByProjects`:191, `renameLegacyPayloadKeys`:280
- Maria's Notebook/Backup/Core/AutoBackupManager.swift — `createPreDestructiveBackup`:170
- Maria's Notebook/Backup/Core/BackupFolderMigration.swift — `resetDismissal`:45
- Maria's Notebook/Backup/Export/BackupSizeEstimator.swift — `measureActualSize`:120
- Maria's Notebook/Backup/SaveCoordinator.swift — `saveWithInfoToast`:102
- Maria's Notebook/Backup/Services/BackupTransactionManager.swift — `rollbackToActiveCheckpoint`:219, `cleanupOldCheckpoints`:278
- Maria's Notebook/BookClub/BookClubSessionEntity.swift — `fetchByPacket`:89
- Maria's Notebook/Components/FilterOrderStore.swift — `saveAreaOrder`:39, `useDefaults`:92
- Maria's Notebook/Components/Modifiers/CardBackgroundModifier.swift — `cardBackgroundGlass`:47
- Maria's Notebook/Components/ObservationsView+AI.swift — `summarizeSelected`:132
- Maria's Notebook/Components/ObservationsView+List.swift — `contextForNote`:218
- Maria's Notebook/Components/View+LargeSheetSizing.swift — `flexibleSheetSizing`:77
- Maria's Notebook/GoingOut/GoingOutViewModel.swift — `createGoingOut`:66
- Maria's Notebook/Lessons/LessonFileStorage.swift — `searchAttachments`:325
- Maria's Notebook/Lessons/LessonOrderMigration.swift — `normalizeSortIndices`:77, `normalizeOrderInSequence`:106
- Maria's Notebook/Lessons/LessonsFilterPersistence.swift — `normalizeAreaKey`:14
- Maria's Notebook/Lessons/LessonsFilterState.swift — `loadFromPersisted`:54, `makePersisted`:91
- Maria's Notebook/Lessons/LessonsGridItem.swift — `sortedWithIntroductionsFirst`:97
- Maria's Notebook/Lessons/LessonsPresentationHistoryProvider.swift — `fetchLastPresentedDates`:16, `fetchPresentationCounts`:56
- Maria's Notebook/Lessons/LessonsRootView/LessonsRootViewReordering.swift — `moveSequenceUpDown`:54, `reorderSectionByDrag`:207, `moveLessonToSection`:282
- Maria's Notebook/Lessons/LessonsViewModel.swift — `ensureInitialOrderInSequenceIfNeeded`:131, `computeLessonStatusInfo`:190
- Maria's Notebook/Models/Extensions/Presentation+Resolved.swift — `wasMigratedFromOldPresentation`:88
- Maria's Notebook/Models/Extensions/WorkModel+Completion.swift — `completionRecords`:8, `latestCompletion`:16
- Maria's Notebook/Models/LessonAssignmentEntity.swift — `unconfirmStudent`:105
- Maria's Notebook/Models/ModelExtensions.swift — `fetchPracticeSessions`:70, `fetchCommonLesson`:308
- Maria's Notebook/Models/Protocols/DenormalizedSchedulable.swift — `normalizeDenormalizedFields`:50
- Maria's Notebook/ObservationMode/MontessoriObservationTags.swift — `isObservationTag`:60
- Maria's Notebook/Planning/PlanningActions.swift — `moveToInbox`:9
- Maria's Notebook/Planning/PlanningDropUtils.swift — `reorderIDs`:23
- Maria's Notebook/Planning/PlanningEngine.swift — `dayShortLabel`:42
- Maria's Notebook/Presentations/PostPresentationFormViewModel.swift — `getFinalEntries`:127
- Maria's Notebook/Presentations/PresentationsCoordinator.swift — `showSchedulePresentation`:75, `showPostPresentation`:80, `showUnifiedWorkflow`:85, `showLessonAssignmentHistory`:90
- Maria's Notebook/Presentations/PresentationsView+Body.swift — `unresolvedWorkCount`:326
- Maria's Notebook/Presentations/UnifiedPresentationWorkflowPanel+WorkCreation.swift — `syncAssignmentToWorkDraft`:486
- Maria's Notebook/Repositories/AttendanceRepository.swift — `createRecord`:78
- Maria's Notebook/Repositories/LessonRepository.swift — `fetchRootStories`:62, `updateLesson`:117
- Maria's Notebook/Repositories/MeetingRepository.swift — `fetchIncompleteMeetings`:53, `createMeeting`:69, `updateMeeting`:93
- Maria's Notebook/Repositories/MeetingTemplateRepository.swift — `fetchActiveTemplate`:58
- Maria's Notebook/Repositories/NoteRepository.swift — `fetchNotesForStudent`:49, `createNote`:76
- Maria's Notebook/Repositories/PresentationRepository.swift — `fetchInboxItems`:54, `fetchScheduled`:59, `fetchActiveAssignments`:72, `updateNotes`:172, `updateFollowUp`:181, `deleteLessonAssignment`:200
- Maria's Notebook/Repositories/ProjectRepository.swift — `fetchActiveProjects`:48, `createProject`:56, `updateProject`:74, `deleteProject`:94, `fetchSessions`:110, `createSession`:122, `updateSession`:144
- Maria's Notebook/Repositories/ReminderRepository.swift — `fetchDueToday`:53, `createReminder`:73, `updateReminder`:97, `deleteReminder`:139
- Maria's Notebook/Repositories/ResourceRepository.swift — `fetchFavorites`:42, `fetchRecents`:46, `updateResource`:86
- Maria's Notebook/Repositories/StudentRepository.swift — `withdrawStudent`:104, `reenrollStudent`:113
- Maria's Notebook/Services/AI/ParshaSuggestionService.swift — `canRefresh`:54
- Maria's Notebook/Services/AIReportService.swift — `generateNarrative`:40, `gatherReportData`:71
- Maria's Notebook/Services/DataQueryService.swift — `invalidateAllCaches`:253, `invalidateStudentsCache`:260
- Maria's Notebook/Services/DatabaseAnalysisService.swift — `analyzeClassroom`:32
- Maria's Notebook/Services/HebrewParshaService.swift — `nextShabbat`:144
- Maria's Notebook/Services/ImportCommitService.swift — `commitLessons`:18
- Maria's Notebook/Services/LessonPlanning/PlanningFeedbackTracker.swift — `linkToPresentation`:42, `recordOutcome`:60, `calibrationSummary`:76
- Maria's Notebook/Services/Migrations/DataCleanupService.swift — `runAllCleanupOperations`:16
- Maria's Notebook/Services/NetworkMonitoring.swift — `stopNetworkMonitoring`:49
- Maria's Notebook/Services/PlanNextLessonService.swift — `existsActive`:80
- Maria's Notebook/Services/ProcedureService.swift — `getProcedureStats`:63, `fetchProcedure`:140
- Maria's Notebook/Services/ReminderSyncService.swift — `getAvailableReminderLists`:181
- Maria's Notebook/Services/SearchIndexService.swift — `removeResult`:73
- Maria's Notebook/Services/ServiceProtocols.swift — `onAppWillResignActive`:33, `onAppDidBecomeActive`:34
- Maria's Notebook/Services/SessionWorkAssignmentService.swift — `createUniformWork`:18, `offeredWorksForSession`:133, `worksSelectedByStudent`:138, `selectionStatus`:146
- Maria's Notebook/Services/StudentAnalysisService.swift — `compareSnapshots`:101
- Maria's Notebook/Services/SupplyService.swift — `fetchSuppliesGroupedByCategory`:43
- Maria's Notebook/Services/SyncRetryLogic.swift — `cancelRetry`:40
- Maria's Notebook/Services/TodoNotificationService.swift — `checkAuthorizationStatus`:27, `rescheduleNotification`:86, `getPendingNotifications`:97
- Maria's Notebook/Services/UnlockNextLessonService.swift — `getNextLessonName`:112
- Maria's Notebook/Services/YearPlanPromotionService.swift — `promote`:50
- Maria's Notebook/Settings/SettingsModifiers.swift — `settingsHighlight`:30
- Maria's Notebook/Sharing/ClassroomPermissions.swift — `assistantWritableEntityNames`:37
- Maria's Notebook/Sharing/PermissionValidation.swift — `validatePermissionsBeforeSave`:19
- Maria's Notebook/Sharing/SharingPreferences.swift — `isCategoryEnabled`:31, `toggleCategory`:36
- Maria's Notebook/Stories/StoriesViewModel.swift — `gradeBands`:57
- Maria's Notebook/Students/LessonDetail/PresentationProgressHelper.swift — `isNeedsAnotherActive`:48
- Maria's Notebook/Students/Meetings/MeetingReviewService.swift — `createReview`:11, `updateReviewNote`:35
- Maria's Notebook/Students/PresentationDetailActions.swift — `planNextLessonInSequence`:126, `toggleWorkCompletion`:200
- Maria's Notebook/Students/PresentationDetailViewModel+StudentActions.swift — `scheduleNextLessonToInbox`:84
- Maria's Notebook/Students/PresentationDetailViewModel.swift — `saveImmediate`:275
- Maria's Notebook/Students/StudentNotesViewModel.swift — `loadMoreIfNeeded`:54
- Maria's Notebook/Students/TestStudentsFilter.swift — `isHidden`:24
- Maria's Notebook/Students/YearPlan/StudentYearPlanViewModel.swift — `lessonFor`:99, `rescheduleEntry`:108
- Maria's Notebook/Utils/AgeUtils.swift — `halfYearAgeString`:227
- Maria's Notebook/Utils/BackupCountHelpers.swift — `makeExistsChecker`:34
- Maria's Notebook/Utils/CSVDuplicateDetection.swift — `buildKeySets`:35
- Maria's Notebook/Utils/CSVHeaderMapping.swift — `validateRequired`:46
- Maria's Notebook/Utils/Collection+Extensions.swift — `dictionaryByID`:7
- Maria's Notebook/Utils/Date+Normalization.swift — `isBeforeDay`:22, `isAfterDay`:29
- Maria's Notebook/Utils/Double+Formatting.swift — `formatAsPercentage`:21
- Maria's Notebook/Utils/KeychainStore.swift — `generateSymmetricKeyBytes`:68
- Maria's Notebook/Utils/NotesHelpers.swift — `notesVisible`:53
- Maria's Notebook/Utils/PerformanceLogger.swift — `measureAsync`:37
- Maria's Notebook/Utils/StringFallbacks.swift — `valueOrFallback`:12, `trimmedValueOrNil`:36
- Maria's Notebook/Utils/View+PlatformStyles.swift — `sheetPresentation`:73, `platformTapGesture`:109, `macOSFocusable`:122
- Maria's Notebook/ViewModels/GiveLessonViewModel.swift — `toggleMode`:156
- Maria's Notebook/ViewModels/Today/TodayCacheManager.swift — `updateStudents`:41, `mergeStudents`:47, `updateLessons`:57, `mergeLessons`:62
- Maria's Notebook/Work/GroupPracticeHelper.swift — `hasSequencePracticeOpportunity`:21, `groupPracticeBadge`:55
- Maria's Notebook/Work/PracticeSessionEntity.swift — `addWorkItem`:215, `removeWorkItem`:233
- Maria's Notebook/Work/PracticeSessionRepository.swift — `fetchGroupSessions`:77, `fetchSoloSessions`:86, `fetchPartnerships`:95
- Maria's Notebook/Work/WorkAging.swift — `urgencyBucket`:253
- Maria's Notebook/Work/WorkCheckInBadge.swift — `checkInCounts`:13
- Maria's Notebook/Work/WorkDetailView+Sheets.swift — `workDetailSheet`:9
- Maria's Notebook/Work/WorkDetailViewModel.swift — `categoryColor`:426

## 6. Small items

Unused private functions (verified):
- `makeInMemoryDescription` — Maria's Notebook/AppCore/CoreDataStack.swift:475
- `formatDueDate` — Maria's Notebook/Components/TodoRow.swift:16
- `formatReminderBadge` — Maria's Notebook/Components/TodoRow.swift:51
- `formatTodoAsText` — Maria's Notebook/Components/TodoRow.swift:62
- `monday` — Maria's Notebook/Inbox/InboxSheetView.swift:52
- `safeFetch` — Maria's Notebook/Inbox/InboxSheetViewModel.swift:357 — unused private duplicate of the project-wide `safeFetch` extension
- `indexForSequence` — Maria's Notebook/Lessons/LessonsViewModel.swift:51
- `updatePresentation` — Maria's Notebook/Presentations/LessonAssignmentDetailSheet.swift:395
- `applyWorkPlanItemDrop` — Maria's Notebook/Presentations/WeekDayColumn.swift:399
- `metadata` — Maria's Notebook/Students/StudentOverviewTab.swift:83

Deprecated members with zero remaining callers (verified by hand):
- `LessonPlanningViewModel.configure(modelContext:mcpClient:)` — Services/LessonPlanning/LessonPlanningViewModel.swift:81
- `LessonPlanningService.init(modelContext:mcpClient:)` — Services/LessonPlanning/LessonPlanningService.swift:29
- `PresentationAssignmentService.scheduleCheckIn(for:schedule:viewContext:)` — Students/LessonDetail/PresentationAssignmentService.swift:130 (whole file is in section 1 anyway)

Legacy `PreviewProvider` structs (superseded by `#Preview`; harmless, stripped from release builds):
- `ParsingOverlay_Previews` — Maria's Notebook/Components/ParsingOverlay.swift:28
- `ScopedNotesSection_Previews` — Maria's Notebook/Components/ScopedNotesSection.swift:185
- `StudentNoteRowView_Previews` — Maria's Notebook/Students/StudentNoteRowView.swift:165

Dead helpers in the unit-test target: 14 symbols (low priority; see `test_target_dead` in /tmp/deadcode_results.json).

Clean categories: no unused asset-catalog entries, no external package dependencies at all, no `#if false` blocks, no orphaned files outside the build (synchronized groups compile everything on disk).

## Caveats & how to act on this

1. **Do not extend this to Core Data entities.** Unused-looking `CD*` entities must stay — removing entities from the model triggers CloudKit re-mirroring and the empty-DB-on-launch bug (schema is additive-only).
2. Analysis is textual (token-level), verified by agents for the file list; the practical safety net is mechanical: delete in batches, build, run the test suite.
3. Deleting section 1 will expose a second wave: code whose only consumers were these files (transitively dead islands). Re-run the scan afterwards.
4. The tree is mid-refactor — if any section-1 file is something you're about to wire up rather than abandoned, keep it; the new `StudentsScopeChips.swift` is referenced and not flagged.
5. For ongoing hygiene consider Periphery (`brew install peripheryapp/periphery/periphery`) — compiler-index-based, catches what token analysis can't (unused params, redundant `public`, write-only properties).
