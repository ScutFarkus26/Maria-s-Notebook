// ModelRowKinds+Projects.swift
// The backup rows of group projects, their sessions and roles, as their
// hand-written DTOs wrote and restored them until "Simplify round two",
// Phase 7 (see ModelRowKinds.swift). The retired project plans (templates,
// template weeks, week roles) stay payload fields no type fills
// (BackupTypes+Projects.swift).

import CoreData
import Foundation

public typealias ProjectDTO = ModelRow<ProjectBackupRow>
public typealias ProjectSessionDTO = ModelRow<ProjectSessionBackupRow>
public typealias ProjectRoleDTO = ModelRow<ProjectRoleBackupRow>

/// A group project; a record with no `id` isn't backed up. `memberStudentIDs`
/// goes out and restores through the typed list (`memberStudentIDsArray`: a
/// blob that won't read goes out as no one; a restore sorts it and drops
/// repeats), so every row has it. `isActive` (v19) and `modifiedAt` leave the
/// record's own when a row lacks them (a new record's is active, changed
/// now). A record without a created date goes out dated now.
public enum ProjectBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "Project",
        filling: ["createdAt"],
        addedLater: ["isActive", "modifiedAt"],
        computed: [
            .computed(
                "memberStudentIDs", .strings, of: CDProject.self, required: true,
                read: { .strings($0.memberStudentIDsArray) },
                write: { project, value, _ in
                    guard case .strings(let ids)? = value else { return }
                    project.memberStudentIDsArray = ids
                }
            )
        ],
        dropsRecordsWithoutID: true
    )
}

/// One meeting of a project; a record with no `id`, no meeting date or a
/// `projectID` that isn't an id isn't backed up. The project id restores
/// upper-cased and files the session under that project when it's here (the
/// app reaches a project's sessions through the link; bug hunt 2026-11-02,
/// #7); one that isn't leaves the link as it is. `templateWeekID` goes out
/// only when it is an id, and restores upper-cased (a row without one clears
/// it). The assignment mode and the selection limits leave the record's own
/// when a row lacks them. A record without a created date goes out dated now.
public enum ProjectSessionBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "ProjectSession",
        filling: ["createdAt"],
        addedLater: ["assignmentModeRaw", "minSelections", "maxSelections"],
        uuidStrings: ["projectID", "templateWeekID"],
        requiring: ["meetingDate", "projectID"],
        parents: [ParentLink(key: "projectID", relationship: "project")],
        dropsRecordsWithoutID: true
    )
}

/// A role children can take in a project; a record with no `id` or a
/// `projectID` that isn't an id isn't backed up. It names its project by id
/// only (upper-cased on restore): there's no link to re-make. A record
/// without a created date goes out dated now.
public enum ProjectRoleBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "ProjectRole",
        filling: ["createdAt"],
        uuidStrings: ["projectID"],
        requiring: ["projectID"],
        dropsRecordsWithoutID: true
    )
}
