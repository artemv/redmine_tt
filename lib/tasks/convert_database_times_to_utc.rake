#  Be sure to correct LOCAL_UTC_OFFSET and back up database prior to running.
namespace :redmine do
  desc 'Migrates existing time values in database to UTC.'
  task :convert_database_times_to_utc => :environment do
    LOCAL_UTC_OFFSET = 1.hours #Time offset of server that Redmine was running on. 1.hours is for e.g. BST.

    [Issue, Journal, Version, Message, Attachment, Project, Changeset, News].each do |klass|

        puts "\n\nUpdating #{klass} timestamps to UTC"
        time_columns = klass.columns.select do |c| 
          [:datetime, :timestamp].include?(c.type)
        end
        klass.all.each do |obj|
          modified = false
          time_columns.each do |c|
            old_value = obj.send("#{c.name}")
            obj.send("#{c.name}=", old_value - LOCAL_UTC_OFFSET) if old_value && old_value < Time.now - 1.5
            modified = true
          end
          if modified
            raise "error saving #{obj}" if !obj.save_with_validation(false)
            print '.'
          end
        end
    end
  end
end
