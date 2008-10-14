namespace :redmine do
  task :reset_attachment_mime_types => :environment do
    attachments = Attachment.all
    puts "#{attachments.size} attachments without content_type found"
    attachments.each do |a|
      if !a.guess_and_fill_mime_type
        puts "no mime type found for file #{a.filename} (#{a.container_type} #{a.container_id})"
      end
      print '.'
    end
  end
end