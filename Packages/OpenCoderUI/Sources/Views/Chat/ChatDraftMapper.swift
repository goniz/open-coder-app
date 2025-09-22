import ExyteChat
import OpenCoderCore

enum ChatDraftMapper {
  static func makeStateDraft(from draft: DraftMessage) -> ChatDraftState {
    let mediaCount = draft.medias.count
    let giphyCount = draft.giphyMedia == nil ? 0 : 1
    let recordingCount = draft.recording == nil ? 0 : 1
    let replyCount = draft.replyMessage == nil ? 0 : 1
    let attachmentCount = mediaCount + giphyCount + recordingCount + replyCount
    let hasUnsupportedAttachments = attachmentCount > 0

    return .init(
      id: draft.id,
      text: draft.text,
      attachmentCount: attachmentCount,
      hasUnsupportedAttachments: hasUnsupportedAttachments
    )
  }
}
