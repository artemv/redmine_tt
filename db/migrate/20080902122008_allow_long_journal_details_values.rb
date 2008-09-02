class AllowLongJournalDetailsValues < ActiveRecord::Migration
  def self.up
    change_column :journal_details, :old_value, :text
    change_column :journal_details, :value, :text
  end

  def self.down
    #no need
  end
end
