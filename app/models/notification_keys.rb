module NotificationKeys
  ISSUE_ADDED = 'issue_added'
  ISSUE_UPDATED = 'issue_updated'
  NEWS_ADDED = 'news_added'
  DOCUMENT_ADDED = 'document_added'
  FILE_ADDED = 'file_added'
  WIKI_EDIT = 'wiki_edit'
  MESSAGE_POSTED = 'message_posted'

  def self.all
    [ISSUE_ADDED, ISSUE_UPDATED, NEWS_ADDED, DOCUMENT_ADDED, FILE_ADDED,
      WIKI_EDIT, MESSAGE_POSTED]
  end
end