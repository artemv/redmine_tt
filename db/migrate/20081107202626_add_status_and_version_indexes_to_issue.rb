class AddStatusAndVersionIndexesToIssue < ActiveRecord::Migration
  def self.up
    add_index "issues", ["status_id", "fixed_version_id"], :name => "issues_status_id_and_fixed_version_id"
  end

  def self.down
    remove_index "issues", :name => "issues_status_id_and_fixed_version_id"
  end
end
