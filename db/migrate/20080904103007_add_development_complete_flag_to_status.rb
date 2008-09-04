class AddDevelopmentCompleteFlagToStatus < ActiveRecord::Migration
  def self.up
    add_column :issue_statuses, :is_development_complete, :boolean, 
      :null => false, :default => 0
    
    ActiveRecord::Base.connection.update("UPDATE issue_statuses " + 
        "SET is_development_complete = 1 WHERE name = 'Resolved'")
  end

  def self.down
    remove_column :issue_statuses, :is_development_complete
  end
end
