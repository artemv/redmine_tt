class ChangeVersionsDescriptionLimit < ActiveRecord::Migration
  def self.up
    change_column :versions, :description, :string, :limit => 3000
  end

  def self.down
    #not needed
  end
end
