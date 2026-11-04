// ModelRowKinds+Community.swift
// The backup rows of community topics and their attachments, as their
// hand-written DTOs wrote and restored them until "Simplify round two",
// Phase 7 (see ModelRowKinds.swift). Proposed solutions were already table
// rows (ModelRowKinds.swift).

import CoreData
import Foundation

public typealias CommunityTopicDTO = ModelRow<CommunityTopicBackupRow>
public typealias CommunityAttachmentDTO = ModelRow<CommunityAttachmentBackupRow>

/// A topic for the community meeting; a record with no `id` isn't backed up.
/// `raisedBy` carries `broughtBy`. `tags` carries the tag list kept in
/// `_tagsData`, read and written through the typed list (a blob that won't
/// decode goes out as no tags), so every row has it.
public enum CommunityTopicBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "CommunityTopic",
        filling: ["createdAt"],
        omitting: ["_tagsData"],
        renaming: ["raisedBy": "broughtBy"],
        computed: [
            .computed(
                "tags", .strings, of: CDCommunityTopicEntity.self, required: true,
                read: { .strings($0.tags) },
                write: { topic, value, _ in
                    guard case .strings(let tags)? = value else { return }
                    topic.tags = tags
                }
            )
        ],
        dropsRecordsWithoutID: true
    )
}

/// A file or photo attached to a topic, as metadata only; a record with no
/// `id` isn't backed up. The bytes aren't backed up, so a restore leaves a
/// record's own (a new one has none). `kind` carries `kindRaw` read through
/// the typed kind (an unknown raw goes out as a file); one that isn't a kind
/// restores as a file. A topic that can't be found leaves the link as it is.
public enum CommunityAttachmentBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "CommunityAttachment",
        filling: ["createdAt"],
        omitting: ["kindRaw", "data"],
        computed: [
            .raw(
                "kind", attribute: "kindRaw", of: CDCommunityAttachment.self,
                read: { $0.kind }, fallback: CommunityAttachmentKind.file
            )
        ],
        parentIDs: ["topicID": "topic"],
        parents: [ParentLink(key: "topicID", relationship: "topic")],
        dropsRecordsWithoutID: true
    )
}
