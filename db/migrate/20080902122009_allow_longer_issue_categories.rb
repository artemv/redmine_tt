class AllowLongerIssueCategories < ActiveRecord::Migration
  def self.up
    change_column :issue_categories, :name, :string, :limit => 50
  end

  def self.down
    #no need
  end
end
