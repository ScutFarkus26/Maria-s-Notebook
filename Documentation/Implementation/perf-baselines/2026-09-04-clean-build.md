# Clean-build baseline — 2026-09-04 (before Phase 0/1 changes)

Command (fresh DerivedData, index store on, Debug, iPhone 17 simulator, Xcode 27.0 beta 27A5237l):

```bash
DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer" \
  xcodebuild -project "Maria's Notebook.xcodeproj" -scheme "Maria's Notebook" \
  -destination "platform=iOS Simulator,name=iPhone 17,OS=27.0" \
  -derivedDataPath <fresh> -showBuildTimingSummary clean build
```

Wall clock: **1:00.06** (424.08 s user, 23.55 s system, 745% CPU).

Type-check warnings at the pre-change threshold (`-warn-long-function-bodies=200`, no expression warning):

- 244 ms — `Notebook/AppCore/RootView/RootDetailContent.swift:97:54: warning: getter for property 'curriculumPlanningContent'`
- 239 ms — `Notebook/Todos/Views/TodoMainView+ContentArea.swift:10:36: warning: getter for property 'todoListContent'`
- 229 ms — `Notebook/Albums/LessonAlbumMatcher.swift:56:17: warning: static method 'candidates(for:library:includeAlreadyLinked:)'`

## Build Timing Summary

```
SwiftCompile (47 tasks) | 442.493 seconds
SwiftEmitModule (1 task) | 36.115 seconds
SwiftDriver (1 task) | 1.978 seconds
CompileAssetCatalogVariant (1 task) | 1.263 seconds
Ld (3 tasks) | 0.668 seconds
DataModelCompile (1 task) | 0.315 seconds
CodeSign (3 tasks) | 0.307 seconds
ExtractAppIntentsMetadata (1 task) | 0.179 seconds
AppIntentsSSUTraining (1 task) | 0.171 seconds
CopySwiftLibs (1 task) | 0.058 seconds
ConstructStubExecutorLinkFileList (1 task) | 0.043 seconds
GenerateAssetSymbols (1 task) | 0.029 seconds
CpResource (7 tasks) | 0.018 seconds
Copy (4 tasks) | 0.017 seconds
RegisterExecutionPolicyException (1 task) | 0.012 seconds
ProcessProductPackagingDER (2 tasks) | 0.008 seconds
WriteAuxiliaryFile (16 tasks) | 0.007 seconds
ProcessInfoPlistFile (1 task) | 0.007 seconds
Touch (1 task) | 0.002 seconds
LinkAssetCatalog (1 task) | 0.001 seconds
ProcessProductPackaging (2 tasks) | 0.001 seconds
SwiftDriver Compilation Requirements (1 task) | 0.001 seconds
SwiftDriver Compilation (1 task) | 0.001 seconds
SwiftMergeGeneratedHeaders (1 task) | 0.001 seconds
Validate (1 task) | 0.000 seconds
```

## Slow type-check list at the new 100 ms thresholds (Phase 4 work list)

Build with `-warn-long-function-bodies=100 -warn-long-expression-type-checking=100` (same machine, same day; this build ran concurrently with the Daybook Assistant build so its wall clock is not comparable). 146 warnings, 62 distinct sites; worst first. Each item gets a distinct `View` struct or an explicit type annotation.

- 269 ms — `AppCore/RootView/RootDetailContent.swift:97:54` — getter for property 'curriculumPlanningContent'
- 255 ms — `Components/OpenWorkGrid.swift:53:25` — getter for property 'body'
- 249 ms — `Students/Meetings/StudentMeetingsTab+HistorySection.swift:9:35` — getter for property 'historySection'
- 224 ms — `Work/Detail/WorkDetailView.swift:133:18` — instance method 'mainContent(work:)'
- 216 ms — `Todos/Views/TodoMainView+Filtering.swift:8:37` — getter for property 'filteredTodos'
- 208 ms — `Students/Roster/StudentsScopeChips.swift:33:18` — instance method 'chip(for:)'
- 204 ms — `AppCore/RootView.swift:236:49` — getter for property 'rootWithQuickActions'
- 203 ms — `Supplies/Services/SupplyService.swift:10:17` — static method 'fetchSupplies(in:category:searchText:)'
- 203 ms — `Components/InboxOrderStore.swift:19:17` — static method 'orderedUnscheduled(from:orderRaw:)'
- 199 ms — `Projects/ProjectSessionDetailView+Content.swift:68:10` — instance method 'studentSelectionRow(studentID:)'
- 198 ms — `Students/Presentations/PresentationDetailActions.swift:8:10` — instance method 'applyEditsToModel(lessonAssignment:editingLessonID:scheduledFor:givenAt:isPresented:notes:needsAnotherPresentation:selectedStudentIDs:studentsAll:lessons:calendar:)'
- 195 ms — `Services/Migrations/DataCleanupService+OrphanCleanup.swift:15:17` — static method 'cleanOrphanedStudentIDs(using:)'
- 193 ms — `Albums/LessonAlbumMatcher.swift:56:17` — static method 'candidates(for:library:includeAlreadyLinked:)'
- 191 ms — `Students/Printing/WorkPrintView+Grouping.swift:19:17` — static method 'computeSequences(workItems:students:)'
- 187 ms — `Projects/StudentSelectionSheet.swift:101:18` — instance method 'workSelectionRow'
- 175 ms — `GoingOut/GoingOutViewModel.swift:22:41` — getter for property 'filteredGoingOuts'
- 164 ms — `BookClub/Sessions/BookClubMeetingRowView.swift:9:25` — getter for property 'body'
- 163 ms — `AppCore/RootView/RootDetailContent.swift:73:44` — getter for property 'studentsContent'
- 159 ms — `AppCore/RootView.swift:130:25` — getter for property 'body'
- 158 ms — `Work/Practice/PracticeSessionComponents.swift:31:18` — instance method 'levelButton'
- 157 ms — `Services/PDFFolderMigrationService.swift:95:25` — static method 'moveSingleFile(fileURL:oldRootPath:newRoot:)'
- 155 ms — `Utils/StudentSortComparator.swift:13:29` — static method 'byFirstName'
- 152 ms — `Work/CheckIns/CalendarCheckInGroup.swift:40:17` — static method 'groups(from:lookup:)'
- 152 ms — `Today/Views/TodayViewHeader.swift:124:52` — getter for property 'attendanceStudentScroll'
- 152 ms — `Backup/Core/BackupPreferencesService.swift:32:17` — static method 'buildPreferencesDTO()'
- 142 ms — `GoingOut/GoingOutEditorSheet.swift:33:25` — getter for property 'body'
- 141 ms — `Students/Meetings/MeetingsWorkflowComponents.swift:204:25` — getter for property 'body'
- 140 ms — `Utils/Date+Normalization.swift:15:10` — instance method 'isSameDay(as:)'
- 140 ms — `Students/Progress/StudentProgressTab.swift:50:25` — getter for property 'body'
- 137 ms — `AppCore/RootView/RootDetailContent.swift:128:45` — getter for property 'resourcesContent'
- 135 ms — `Backup/Services/BackupTransactionManager.swift:111:17` — instance method 'executeWithRollback(viewContext:mode:shouldCreateCheckpoint:progress:makeCheckpoint:importBody:)'
- 133 ms — `Todos/Support/TodoDateParser.swift:189:25` — static method 'nextWeekday(_:after:skipThisWeek:)'
- 132 ms — `Backup/RestorePreviewView.swift:176:19` — expression
- 127 ms — `Work/Support/SchoolDayChecker.swift:21:29` — static method 'isNonSchoolDay(_:nonSchoolDayDates:overrideDates:calendar:)'
- 122 ms — `Todos/Views/TodoExportView.swift:217:25` — getter for property 'body'
- 119 ms — `Students/Roster/StudentsView.swift:76:25` — getter for property 'body'
- 117 ms — `Resources/ResourceTagPicker.swift:49:25` — getter for property 'body'
- 116 ms — `Students/Detail/StudentLearningWorkspace.swift:31:25` — getter for property 'body'
- 116 ms — `SmallSequencePlanner/SmallSequencePlannerViewModel.swift:87:18` — instance method 'buildCandidates(students:context:)'
- 116 ms — `AppCore/MariasNotebookApp+MainWindow.swift:31:35` — getter for property 'appFlowContent'
- 114 ms — `Components/ClassSubjectChecklistView.swift:17:28` — expression
- 111 ms — `Backup/Core/BackupPreferencesService.swift:65:16` — expression
- 111 ms — `AppCore/RootView/RootDetailContent.swift:103:34` — expression
- 109 ms — `Parsha/ParshaCalendarView.swift:73:25` — getter for property 'body'
- 108 ms — `Students/Presentations/PresentationDetailView.swift:332:51` — getter for property 'postPresentationCaptureContent'
- 107 ms — `AppCore/MariasNotebookApp+MainWindow.swift:48:33` — getter for property 'readyContent'
- 106 ms — `Components/SubjectGrainPill.swift:92:25` — getter for property 'body'
- 106 ms — `AppCore/RootView.swift:665:5` — expression
- 105 ms — `Today/ViewModels/TodayViewModel.swift:383:18` — instance method 'listIDsMatch'
- 103 ms — `PerpetualCalendar/PlanningCalendarView.swift:128:18` — instance method 'planningDayCell(cellID:isToday:isNonSchool:)'
- 103 ms — `GoingOut/GoingOutDetailView.swift:27:25` — getter for property 'body'
- 103 ms — `Components/Shared/WorkflowProgressIndicator.swift:10:44` — getter for property 'progressPercentage'
- 103 ms — `AppCore/AppIntents.swift:97:44` — getter for static property 'appShortcuts'
- 102 ms — `Today/Views/AgendaItemRows.swift:71:25` — getter for property 'body'
- 101 ms — `Work/Agenda/WorksAgendaView.swift:309:5` — expression
- 100 ms — `Students/Progress/StudentSubjectProgressionViewModel.swift:25:10` — instance method 'configure(for:area:sequence:context:)'
