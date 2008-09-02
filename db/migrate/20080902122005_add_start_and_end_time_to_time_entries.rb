class AddStartAndEndTimeToTimeEntries < ActiveRecord::Migration
  def self.up
    add_column :time_entries, :start_time, :datetime
    add_column :time_entries, :end_time, :datetime
  end

  def self.down
    remove_column :time_entries, :start_time
    remove_column :time_entries, :end_time
  end
end
