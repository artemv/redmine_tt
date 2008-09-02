class AllowNullTimeEntryHours < ActiveRecord::Migration
  def self.up
    change_column :time_entries, :hours, :float, :null => true
  end

  def self.down
    # not needed
  end
end
