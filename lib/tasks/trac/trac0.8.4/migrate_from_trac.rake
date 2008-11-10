# redMine - project management software
# Copyright (C) 2006-2007  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require 'active_record'
require 'iconv'
require 'pp'

namespace :redmine do
  LINEFEED_HACK_START = "<pre class=\"linebreak\">"
  LINEFEED_HACK_END = "\n</pre>"

  def fix_linebreaks_in_tables(text)
    buffer = nil
    text.gsub! "\r\n", "\n"
    
    fixed = false
    rows = text.split("\n")
    in_table = false
    sum = rows.inject([]) do |sum, row|
      if buffer
        puts "accumulating #{row.inspect} to buffer"
        buffer += "#{LINEFEED_HACK_START}#{LINEFEED_HACK_END}" + row
        if row.strip.ends_with?("|")
          sum << buffer
          buffer = nil
          puts "flushed buffer"
        end
      else 
        if row.starts_with?("|")
          in_table = true
          if row.strip.ends_with?("|") || row[LINEFEED_HACK_START]
            sum << row
          else
            buffer = row
            fixed = true
            puts "buffer started with row #{row.inspect}"
          end
        else
          if in_table && !row.strip.empty?
            sum << '' #add empty line after table if there's no one
          end
          in_table = false
          sum << row
        end
      end
      sum
    end
    sum << buffer + "|" if buffer
    sum.join("\n") if fixed
  end
  

  desc 'Trac migration script'
  task :migrate_from_trac_08_4 => :environment do
    
    module TracMigrate
        ID_SHIFTS = {:mla => 60000, :"city-and-hackney" => 70000, 
          :vrg => 80000, :mhmds => 90000, :hps => 100000, 
          :"soltex-core" => 110000, :"bml-maps" => 120000, 
          :"healey-baker" => 130000, :bicut => 140000, :nduw => 150000, 
          :"ics-demo" => 160000, :"sve" => 170000, 
          :"tt-web-site" => 180000, :rap => 190000}
     
        DEFAULT_STATUS = IssueStatus.default
        pending_status = IssueStatus.find_by_name('Pending')
        implementation_status = IssueStatus.find_by_name('Implementation')
        resolved_status = IssueStatus.find_by_name('Resolved')
        feedback_status = IssueStatus.find_by_name('Discussion')
        closed_status = IssueStatus.find_by_name('Closed')
        STATUS_MAPPING = {'new' => pending_status,
                          'discussion' => feedback_status,
                          'settled' => implementation_status,
                          'implementation' => implementation_status,
                          'pending' => pending_status,
                          'done' => resolved_status,
                          'closed' => closed_status,
                          'Accepted' => pending_status,
                          'Proposed' => pending_status,
                          'Archieved' => pending_status,
                          }
	                          
        priorities = Enumeration.get_values('IPRI')
        DEFAULT_PRIORITY = priorities[0]
        PRIORITY_MAPPING = {
                            'Low' => priorities[0],
                            'Medium' => priorities[1],
                            'High' => priorities[2],
                            }
      
        TRACKER_BUG = Tracker.find_by_name('Bug')
        TRACKER_FEATURE = Tracker.find_by_name('Feature')
        TRACKER_SUPPORT = Tracker.find_by_name('Support')
        DEFAULT_TRAC_TYPE = 'Support'
        TRACKER_MAPPING = {'Defect' => TRACKER_BUG,
                           'New feature' => TRACKER_FEATURE,
                           'Support' => TRACKER_SUPPORT,
                           }
        
        manager_role = Role.find_by_name('Manager')
        developer_role = Role.find_by_name('Developer')
        reporter_role = Role.find_by_name('Reporter')
        DEFAULT_ROLE = developer_role
        ROLE_MAPPING = {'admin' => manager_role,
                        'developer' => developer_role,
                        'reporter' => reporter_role,
                        }        

        TYPE_CUSTOM_FIELD = 'type'
        ADDITIONAL_RESOLUTIONS = ['fixed/done', 'invalid', 'cancelled', 
            'duplicate', 'works for me']
        
        RESOLUTION_CORRECTIONS = {'canceled' => 'cancelled', 
          'fixed' => 'fixed/done', 'wontfix' => 'cancelled'}
        
        REPRODUCED_AT_REMAP = {'Production' => 'Prod', 'UAT' => 'UAT',
          'Dev' => 'Dev', 'Dev (TTA02)' => 'Moscow', 'Dev (Msc)' => 'Moscow', 
          'Dev(Msc)' => 'Moscow', 'Preview (Msc)' => 'Moscow', 
          :unknown => 'Prod'}
                        
      class ::Time
        class << self
          alias :real_now :now
          def now
            real_now - @fake_diff.to_i
          end
          def fake(time)
            @fake_diff = real_now - time
            res = yield
            @fake_diff = 0
           res
          end
        end
      end

      class TracComponent < ActiveRecord::Base
        set_table_name :component
      end
  
      class TracMilestone < ActiveRecord::Base
        set_table_name :milestone
        
        def due
          if read_attribute(:due) && read_attribute(:due) > 0
            Time.at(read_attribute(:due)).to_date
          else
            nil
          end
        end

        def description
          # Attribute is named descr in Trac v0.8.x
          has_attribute?(:descr) ? read_attribute(:descr) : read_attribute(:description)
        end
      end
      
      class TracTicketCustom < ActiveRecord::Base
        set_table_name :ticket_custom
      end
      
      class TracAttachment < ActiveRecord::Base
        set_table_name :attachment
        set_inheritance_column :none
        
        def time; Time.at(read_attribute(:time)) end
        
        def original_filename
          filename
        end
        
        def content_type
          Redmine::MimeType.of(filename) || ''
        end
        
        def exist?
          File.file? trac_fullpath
        end
        
        def read
          File.open("#{trac_fullpath}", 'rb').read
        end
        
        def description
          read_attribute(:description).to_s.slice(0,255)
        end
        
        def trac_fullpath
          attachment_type = read_attribute(:type)
          trac_file = filename.gsub( /[^a-zA-Z0-9\-_\.!~*']/n ) {|x| sprintf('%%%02X', x[0]) }
          trac_file.gsub!("'", "%27")
          "#{TracMigrate.trac_attachments_directory}/#{attachment_type}/#{id}/#{trac_file}"
        end
      end
      
      class TracTicket < ActiveRecord::Base
        set_table_name :ticket
        set_inheritance_column :none
        
        # ticket changes: only migrate status changes and comments
        has_many :changes, :class_name => "TracTicketChange", :foreign_key => :ticket
        has_many :attachments, :class_name => "TracAttachment", :foreign_key => :id, :conditions => "#{TracMigrate::TracAttachment.table_name}.type = 'ticket'"
        has_many :customs, :class_name => "TracTicketCustom", :foreign_key => :ticket
        
        def ticket_type
          custom = customs.find_by_name(TYPE_CUSTOM_FIELD)
          type = custom ? custom.value : DEFAULT_TRAC_TYPE
          type = DEFAULT_TRAC_TYPE if type.blank?
          type
        end
        
        def summary
          read_attribute(:summary).blank? ? "(no subject)" : read_attribute(:summary)
        end
        
        def description
          read_attribute(:description).blank? ? summary : read_attribute(:description)
        end
        
        def time; Time.at(read_attribute(:time)) end
        def changetime; Time.at(read_attribute(:changetime)) end
      end
      
      class TracTicketChange < ActiveRecord::Base
        set_table_name :ticket_change
        
        def time; Time.at(read_attribute(:time)) end
      end
      
      TRAC_WIKI_PAGES = %w(InterMapTxt InterTrac InterWiki RecentChanges SandBox TracAccessibility TracAdmin TracBackup TracBrowser TracCgi TracChangeset \
                           TracEnvironment TracFastCgi TracGuide TracImport TracIni TracInstall TracInterfaceCustomization \
                           TracLinks TracLogging TracModPython TracNotification TracPermissions TracPlugins TracQuery \
                           TracReports TracRevisionLog TracRoadmap TracRss TracSearch TracStandalone TracSupport TracSyntaxColoring TracTickets \
                           TracTicketsCustomFields TracTimeline TracUnicode TracUpgrade TracWiki WikiDeletePage WikiFormatting \
                           WikiHtml WikiMacros WikiNewPage WikiPageNames WikiProcessors WikiRestructuredText WikiRestructuredTextLinks \
                           CamelCase TitleIndex)
      
      class TracWikiPage < ActiveRecord::Base
        set_table_name :wiki
        set_primary_key :name
        
        has_many :attachments, :class_name => "TracAttachment", :foreign_key => :id, :conditions => "#{TracMigrate::TracAttachment.table_name}.type = 'wiki'"
        
        def self.columns
          # Hides readonly Trac field to prevent clash with AR readonly? method (Rails 2.0)
          super.select {|column| column.name.to_s != 'readonly'}
        end
        
        def time; Time.at(read_attribute(:time)) end
      end
      
      class TracPermission < ActiveRecord::Base
        set_table_name :permission  
      end
      
      class TracSessionAttribute < ActiveRecord::Base
        set_table_name :session_attribute
      end

      class UserInfo
        attr_accessor :login, :first_name, :last_name, :email, :ldap
        
        def initialize(hash)
          hash.each {|key, value| send "#{key}=", value}
        end
        
        def self.load_dir
          dir = {}
          File.open('users') do |file|
            file.each_line do |line|
              parts = line.strip.split
              
              info = UserInfo.new :first_name => parts[0], 
                  :last_name => parts[1], :login => parts[2], 
                  :email => parts[3], :ldap => true
              
              dir["#{info.first_name} #{info.last_name}"] = info
            end
          end
          @@userdir = dir
        end
        
        def self.find_by_name(name)
          @@userdir[name]
        end
        
        load_dir
      end
           
      USER_INFO = YAML::load(File.open('user_info.yml'))

      def self.by_ext_map(trac_username, map)
        ext_value = map[trac_username]
        return nil if !ext_value

        login, fn, ln = yield ext_value

        UserInfo.new({:login => login, :first_name => fn, 
            :last_name => ln, :email => "#{login}@foo.bar", 
            :ldap => false})        
      end
      
      def self.get_user_info(trac_username)
        
        #sometimes trac_username is Ivan Smirnov
        result = UserInfo.find_by_name(trac_username)
        
        #sometimes trac_username is previous-version Trac login of user
        result = UserInfo.find_by_name(USER_INFO[:mapping][trac_username]) if !result
        
        #sometimes trac_username relates to user that is not in LDAP (anymore)
        if !result
          #sometimes trac_username is Ivan Smirnov
          result = by_ext_map(trac_username, USER_INFO[:ext].invert) do |value| 
            [value] + trac_username.split
          end 
          
          #sometimes trac_username is previous-version Trac login of user
          result = by_ext_map(trac_username, USER_INFO[:ext]) do |value| 
            [trac_username] + value.split
          end if !result
          
          raise "trac user '#{trac_username}' is not mapped to Redmine login " + 
              "nor to external user name!" if !result
        end
        result
      end
      
      def self.find_or_create_user(trac_username, project_member = false)
        return User.anonymous if trac_username.blank?
        
        user_info = get_user_info(trac_username)
        u = User.find_by_login(user_info.login)
        u = User.find_by_mail(user_info.email) if !u
        if !u          
          u = User.new :mail => user_info.email,
                       :firstname => user_info.first_name,
                       :lastname => user_info.last_name

          u.login = user_info.login
          if user_info.ldap
            u.auth_source = AuthSourceLdap.find(:all)[0] 
            #u.admin = true #if TracPermission.find_by_username_and_action(username, 'admin')
          else
            u.password = 'trac'
          end
          if !u.save
            raise "couldn't save user: #{u.errors.inspect}"
          end           
        end
        # Make sure he is a member of the project
        if project_member && !u.member_of?(@target_project)
          role = DEFAULT_ROLE
          if u.admin
            role = ROLE_MAPPING['admin']
          elsif TracPermission.find_by_username_and_action(trac_username, 'developer')
            role = ROLE_MAPPING['reporter']
          end
          Member.create(:user => u, :project => @target_project, :role => role)
          u.reload
        end
        u
      end
      
      def self.project_ids_shift
        ID_SHIFTS[@target_project.identifier.to_sym]
      end
      
      def self.new_ticket_id(old_id)
        shift = project_ids_shift
        raise "ID shift not defined for project #{@target_project.identifier}!" if !shift
        old_id.to_i + shift
      end
      
      # Basic wiki syntax conversion
      def self.convert_wiki_text(text)
        # Titles
        text = text.gsub(/^(\=+)\s(.+)\s(\=+)/) {|s| "\nh#{$1.length}. #{$2}\n"}
        # External Links
        text = text.gsub(/\[(http[^\s]+)\s+([^\]]+)\]/) {|s| "\"#{$2}\":#{$1}"}
        
        text = text.gsub(/\[\[BR\]\]/, "\n") # This has to go before the rules below
        text = text.gsub(/\[\[br\]\]/, "\n") 
        
        # Internal Links
        text = text.gsub(/\[\"(.+)\".*\]/) {|s| "[[#{$1.delete(',./?;|:')}]]"}
        text = text.gsub(/\[wiki:\"(.+)\".*\]/) {|s| "[[#{$1.delete(',./?;|:')}]]"}
        text = text.gsub(/\[wiki:\"(.+)\".*\]/) {|s| "[[#{$1.delete(',./?;|:')}]]"}
        text = text.gsub(/\[wiki:([^\s\]]+)\]/) {|s| "[[#{$1.delete(',./?;|:')}]]"}
        text = text.gsub(/\[wiki:([^\s\]]+)\s(.*)\]/) {|s| "[[#{$1.delete(',./?;|:')}|#{$2.delete(',./?;|:')}]]"}

	# Links to pages UsingJustWikiCaps
	text = text.gsub(/([^!]|^)(^| )([A-Z][a-z]+[A-Z][a-zA-Z]+)/, '\\1\\2[[\3]]')
	# Normalize things that were supposed to not be links
	# like !NotALink
	text = text.gsub(/(^| )!([A-Z][A-Za-z]+)/, '\1\2')
        # Revisions links
        text = text.gsub(/\[(\d+)\]/, 'r\1')
        # Ticket number re-writing
        text = text.gsub(/#(\d+)/) do |s|
          if $1.length < 10
            "\##{new_ticket_id($1.to_i)}"
          else
            s
          end
        end
        # Preformatted blocks
        text = text.gsub(/\{\{\{/, '<pre>')
        text = text.gsub(/\}\}\}/, '</pre>')          
        # Highlighting
        text = text.gsub(/'''''([^\s])/, '_*\1')
        text = text.gsub(/([^\s])'''''/, '\1*_')
        text = text.gsub(/'''/, '*')
        text = text.gsub(/''/, '_')
        text = text.gsub(/__/, '+')
        text = text.gsub(/~~/, '-')
        text = text.gsub(/`/, '@')
        text = text.gsub(/,,/, '~')        
        # Lists
        text = text.gsub(/^([ ]+)\* /) {|s| '*' * $1.length + " "}

        #tables
        text = text.split("\r\n").map do |line|
          if line.starts_with? '||'
            line.gsub! '||', '|'
            line += '|' if !line.ends_with? '||'
          end
          line
        end.join "\n"

        #anti-linebreaks-in-tables measure
        fixed = fix_linebreaks_in_tables(text)
        text = fixed if fixed

        text
      end
    
      def self.maybe_remap(value, map, options = {})
        remapped = map[value]
        if options[:force] && !remapped
          remapped = map[:unknown]
          raise "Remapped value for '#{value}' not found. You can specify :unknown in map to solve this." if !remapped
        end
        remapped || value
      end
      
      def self.get_string(trac_value, model, field, options = {})
        options.reverse_merge :encode => true
        value = trac_value
        value = encode(value) if options[:encode]
        size = value.size
        limit = limit_for(model, field)
        if limit && limit < size
          cut = value[0..limit-1]
          msg = ''
          msg += options[:context_hint] + ': ' if options[:context_hint]
          msg += "Trac's string \n'#{value}'\n (#{size} symbols) doesn't fit into " + 
            "Redmine's #{model}.#{field} (#{limit} max). Cutting to \n'#{cut}'" 
          puts msg
          value = cut
        end
        
        value
      end

      def self.migrate
        establish_connection

        # Quick database test
        TracComponent.count
                
        migrated_components = 0
        migrated_milestones = 0
        migrated_tickets = 0
        migrated_custom_values = 0
        migrated_ticket_attachments = 0
        migrated_wiki_edits = 0      
        migrated_wiki_attachments = 0
  
        # Components
        print "Migrating components"
        issues_category_map = {}
        TracComponent.find(:all).each do |component|
      	print '.'
      	STDOUT.flush
          c = IssueCategory.new :project => @target_project,
                                :name => get_string(component.name, IssueCategory, 'name')
      	if !c.save
      	  raise "error saving category: #{c.errors.inspect}. Trac component is #{component.inspect}"
      	end
      	issues_category_map[component.name] = c
      	migrated_components += 1
        end
        puts
        
        # Milestones
        print "Migrating milestones"
        version_map = {}
        TracMilestone.find(:all).each do |milestone|
          print '.'
          STDOUT.flush
          i = Version.new :project => @target_project,
                          :name => get_string(milestone.name, Version, 'name'),
                          :description => get_string(convert_wiki_text(encode(milestone.descr)), Version, 'description', :encode => false)
          i.effective_date = Time.at(milestone.time).to_date if milestone.time > 0
          i.save!
          version_map[milestone.name] = i
          migrated_milestones += 1
        end
        puts
        #return

        # Custom fields
        # TODO: read trac.ini instead
        print "Migrating custom fields"
        custom_field_map = {}
        TracTicketCustom.find_by_sql("SELECT DISTINCT name FROM #{TracTicketCustom.table_name}").each do |field|
          next if field.name == TYPE_CUSTOM_FIELD #we're going to write type as tracker
          print '.'
          STDOUT.flush
          # Redmine custom field name
          field_name = get_string(field.name, IssueCustomField, 'name').humanize
          # Find if the custom already exists in Redmine
          f = IssueCustomField.find_by_name(field_name)
          # Or create a new one
          f ||= IssueCustomField.create(:name => get_string(field.name, IssueCustomField, 'name').humanize,
                                        :field_format => 'string')
                                   
          raise "couldn't save custom field definition. Errors: #{f.errors.inspect}" if f.new_record?
          f.trackers = Tracker.find(:all)
          f.projects << @target_project
          custom_field_map[field.name] = f
        end
        puts
        
        # Trac 'resolution' field as a Redmine custom field
        r = IssueCustomField.find(:first, :conditions => { :name => "Resolution" })
        r = IssueCustomField.new(:name => 'Resolution',
                                 :field_format => 'list',
                                 :is_filter => true) if r.nil?
        r.trackers = Tracker.find(:all)
        r.projects << @target_project
        r.possible_values = (r.possible_values + ADDITIONAL_RESOLUTIONS).flatten.compact.uniq
        r.save!
        @@resolution_custom_field = r
            
        # Trac 'version' field as a Redmine custom field 'Reproduced at'
        r = IssueCustomField.find(:first, :conditions => { :name => 'Reproduced at' })
        r = IssueCustomField.new(:name => 'Reproduced at',
                                 :field_format => 'list',
                                 :is_filter => true) if r.nil?
        r.trackers = [TRACKER_BUG]
        r.projects << @target_project
        r.possible_values = (r.possible_values + [REPRODUCED_AT_REMAP.values]).flatten.compact.uniq
        r.save!
        @@reproduced_at_custom_field = r
        
        # Tickets
        print "Migrating tickets"
          TracTicket.find(:all, :order => 'id ASC', :conditions => 'id >= 0').each do |ticket|
            begin
        	print '.'
        	STDOUT.flush
        	i = Issue.new :project => @target_project, 
                          :subject => get_string(ticket.summary, Issue, 'subject', :context_hint => 'Ticket %d' % ticket.id),
                          :description => get_string(convert_wiki_text(encode(ticket.description)), Issue, :description, :encode => false),
                          :priority => PRIORITY_MAPPING[ticket.priority],
                          :created_on => ticket.time
        	raise "couldn't find priority for Trac priority '#{ticket.priority}'" if !i.priority
        	i.author = find_or_create_user(ticket.reporter)
        	i.category = issues_category_map[ticket.component] unless ticket.component.blank?
        	i.fixed_version = version_map[ticket.milestone] unless ticket.milestone.blank?
        	i.status = STATUS_MAPPING[ticket.status]
        	raise "couldn't find status for Trac status '#{ticket.status}'" if !i.status
        	i.tracker = TRACKER_MAPPING[ticket.ticket_type]
        	raise "couldn't find tracker for Trac ticket type '#{ticket.ticket_type}'" if !i.tracker
        	ticket_id = new_ticket_id(ticket.id)
        	raise "Ticket with id #{ticket_id} already exist!" if Issue.exists?(ticket_id)
                i.id = ticket_id
                #% done
                i.done_ratio = 100 if i.status.is_closed?
                
        	Time.fake(ticket.changetime) do 
                  begin
                    i.save!
                  rescue Exception => e
                    puts "ticket type: #{ticket.ticket_type}"
                    puts "issue tracker: #{i.tracker.inspect}"
                    puts "project trackers: #{i.project.trackers.inspect}"
                    raise e
                  end
                end
                
                #resolution
        	if ticket.resolution.blank?
        	    #puts "resolution is blank"
        	else
                    cv = i.custom_values.find_by_custom_field_id(@@resolution_custom_field.id)
            	    cv.value = maybe_remap(ticket.resolution, 
                        RESOLUTION_CORRECTIONS)

            	    res = cv.save
                    raise "error saving resolution: #{cv.errors.inspect}" if !res
          	end 
                
                #version
                if !ticket.version.blank? && @@reproduced_at_custom_field.trackers.include?(i.tracker)
                    cv = i.custom_values.find_by_custom_field_id(@@reproduced_at_custom_field.id)
            	    cv.value = maybe_remap(ticket.version, REPRODUCED_AT_REMAP,
                      :force => true)

            	    res = cv.save
                    raise "error saving version: #{cv.errors.inspect}" if !res                  
                end
        	migrated_tickets += 1
        	
        	# Owner
            unless ticket.owner.blank?
              i.assigned_to = find_or_create_user(ticket.owner, true)
              Time.fake(ticket.changetime) { i.save!}
            end
      	
        	# Comments and status/resolution changes
        	ticket.changes.group_by(&:time).each do |time, changeset|
              status_change = changeset.select {|change| change.field == 'status'}.first
              resolution_change = changeset.select {|change| change.field == 'resolution'}.first
              version_change = changeset.select {|change| change.field == 'version'}.first
              comment_change = changeset.select {|change| change.field == 'comment'}.first
              owner_change = changeset.select {|change| change.field == 'owner'}.first
              milestone_change = changeset.select {|change| change.field == 'milestone'}.first
              
              n = Journal.new :notes => (comment_change ? get_string(convert_wiki_text(encode(comment_change.newvalue)), Journal, 'notes', :encode => false) : ''),
                              :created_on => time
              n.user = find_or_create_user(changeset.first.author)
              n.journalized = i
              if status_change && 
                   STATUS_MAPPING[status_change.oldvalue] &&
                   STATUS_MAPPING[status_change.newvalue] &&
                   (STATUS_MAPPING[status_change.oldvalue] != STATUS_MAPPING[status_change.newvalue])
                n.details << JournalDetail.new(:property => 'attr',
                                               :prop_key => 'status_id',
                                               :old_value => STATUS_MAPPING[status_change.oldvalue].id,
                                               :value => STATUS_MAPPING[status_change.newvalue].id)
              end
              if resolution_change
                n.details << JournalDetail.new(:property => 'cf',
                                               :prop_key => @@resolution_custom_field.id,
                                               :old_value => maybe_remap(resolution_change.oldvalue, RESOLUTION_CORRECTIONS),
                                               :value => maybe_remap(resolution_change.newvalue, RESOLUTION_CORRECTIONS))
              end
              
              if version_change && @@reproduced_at_custom_field.trackers.include?(i.tracker)
                n.details << JournalDetail.new(:property => 'cf',
                                               :prop_key => @@reproduced_at_custom_field.id,
                                               :old_value => maybe_remap(version_change.oldvalue, REPRODUCED_AT_REMAP, :force => true),
                                               :value => maybe_remap(version_change.newvalue, REPRODUCED_AT_REMAP, :force => true))
              end
              
              if owner_change
                n.details << JournalDetail.new(:property => 'attr',
                                               :prop_key => 'assigned_to_id',
                                               :old_value => find_or_create_user(owner_change.oldvalue, true).id,
                                               :value => find_or_create_user(owner_change.newvalue, true).id)
              end
              
              if milestone_change
                old = Version.find_by_name(milestone_change.oldvalue)
                old = old.id if old
                new = Version.find_by_name(milestone_change.newvalue)
                new = new.id if new
                n.details << JournalDetail.new(:property => 'attr',
                                               :prop_key => 'fixed_version_id',
                                               :old_value => old,
                                               :value => new)
              end
              n.save unless n.details.empty? && n.notes.blank?
        	end
        	
        	# Attachments
        	ticket.attachments.each do |attachment|
        	  if !attachment.exist?
        	    puts "attachment #{attachment.inspect} (full path '#{attachment.trac_fullpath}') doesn't exist! (skipping)"
        	    next
        	  end
              a = Attachment.new :created_on => attachment.time
              a.file = attachment
              a.author = find_or_create_user(attachment.author)
              a.container = i
              a.description = attachment.description
              if a.save
                migrated_ticket_attachments += 1 
              else
                puts "error saving attachment (ignoring): #{a.errors.inspect}"
              end
        	end
        	
        	# Custom field values
        	ticket.customs.each do |custom|
        	  if custom_field_map[custom.name].nil?
        	    puts "custom field #{custom.inspect} not found in custom_field_map" if custom.name != TYPE_CUSTOM_FIELD
        	    next
        	  end
                  cv = CustomValue.new :custom_field => custom_field_map[custom.name],
                                      :value => custom.value
                  cv.customized = i
                  if !cv.save                
                    puts "error saving custom attribute (ignoring): #{cv.errors.inspect}"
                    next
                  end
                  migrated_custom_values += 1
        	end
          rescue Exception => e
            puts "error migrating Trac ticket #{ticket.inspect}"
            raise e
          end
        end
        
        # update issue id sequence if needed (postgresql)
        Issue.connection.reset_pk_sequence!(Issue.table_name) if Issue.connection.respond_to?('reset_pk_sequence!')
        puts
        
        sample_id = @target_project.issues.find(:all, :conditions => 
            ('id > %d' % project_ids_shift), :limit => 3).last.id
        
        @target_project.description = '' if !@target_project.description
        @target_project.description += "\r\n\r\n" if !@target_project.description.blank?
        @target_project.description += %Q{
*If you are looking for an old ticket created in Trac, add #{project_ids_shift} to the old ticket number.* 
For example, the old ticket number #{sample_id - project_ids_shift} became ##{sample_id}.\r\n\r\n
*To navigate to a ticket by number, enter the number into the Search field (at the top-right of the page) and press Enter key.*}
        @target_project.save!

        # Wiki      
        wiki_edit_count = TracWikiPage.find(:all).size
=begin
        print "Migrating wiki"
        @target_project.wiki.destroy if @target_project.wiki
        @target_project.reload
        wiki = Wiki.new(:project => @target_project, :start_page => 'WikiStart')
        wiki_edit_count = 0
        if wiki.save
          TracWikiPage.find(:all, :order => 'name, version').each do |page|
            # Do not migrate Trac manual wiki pages
            next if TRAC_WIKI_PAGES.include?(page.name)
            wiki_edit_count += 1
            print '.'
            STDOUT.flush
            p = wiki.find_or_new_page(page.name)
            p.content = WikiContent.new(:page => p) if p.new_record?
            p.content.text = page.text
            p.content.author = find_or_create_user(page.author) unless page.author.blank? || page.author == 'trac'
            p.content.comments = page.comment
            Time.fake(page.time) { p.new_record? ? p.save : p.content.save }
            
            next if p.content.new_record?
            migrated_wiki_edits += 1 
            
            # Attachments
            page.attachments.each do |attachment|
              next unless attachment.exist?
              next if p.attachments.find_by_filename(attachment.filename.gsub(/^.*(\\|\/)/, '').gsub(/[^\w\.\-]/,'_')) #add only once per page
              a = Attachment.new :created_on => attachment.time
              a.file = attachment
              a.author = find_or_create_user(attachment.author)
              a.description = attachment.description
              a.container = p
              migrated_wiki_attachments += 1 if a.save
            end
          end
          
          wiki.reload
          wiki.pages.each do |page|
            page.content.text = convert_wiki_text(page.content.text)
            Time.fake(page.content.updated_on) { page.content.save }
          end
        end
=end        
        puts
        
        puts
        puts "Components:      #{migrated_components}/#{TracComponent.count}"
        puts "Milestones:      #{migrated_milestones}/#{TracMilestone.count}"
        puts "Tickets:         #{migrated_tickets}/#{TracTicket.count}"
        puts "Ticket files:    #{migrated_ticket_attachments}/" + TracAttachment.count(:conditions => {:type => 'ticket'}).to_s
        puts "Custom values:   #{migrated_custom_values}/#{TracTicketCustom.count(:conditions => "name <> '#{TYPE_CUSTOM_FIELD}'")}"
        puts "Wiki edits:      #{migrated_wiki_edits}/#{wiki_edit_count}"
        puts "Wiki files:      #{migrated_wiki_attachments}/" + TracAttachment.count(:conditions => {:type => 'wiki'}).to_s
      end
      
      def self.limit_for(klass, attribute)
        klass.columns_hash[attribute.to_s].limit
      end
      
      def self.encoding(charset)
        @ic = Iconv.new('UTF-8', charset)
      rescue Iconv::InvalidEncoding
        puts "Invalid encoding!"
        return false
      end
      
      def self.set_trac_directory(path)
        @@trac_directory = path
        raise "This directory doesn't exist!" unless File.directory?(path)
        raise "#{trac_attachments_directory} doesn't exist!" unless File.directory?(trac_attachments_directory)
        @@trac_directory
      rescue Exception => e
        puts e
        return false
      end

      def self.trac_directory
        @@trac_directory
      end

      def self.set_trac_adapter(adapter)
        return false if adapter.blank?
        raise "Unknown adapter: #{adapter}!" unless %w(sqlite sqlite3 mysql postgresql).include?(adapter)
        # If adapter is sqlite or sqlite3, make sure that trac.db exists
        raise "#{trac_db_path} doesn't exist!" if %w(sqlite sqlite3).include?(adapter) && !File.exist?(trac_db_path)
        @@trac_adapter = adapter
      rescue Exception => e
        puts e
        return false
      end
      
      def self.set_trac_db_host(host)
        return nil if host.blank?
        @@trac_db_host = host
      end

      def self.set_trac_db_port(port)
        return nil if port.to_i == 0
        @@trac_db_port = port.to_i
      end
      
      def self.set_trac_db_name(name)
        return nil if name.blank?
        @@trac_db_name = name
      end

      def self.set_trac_db_username(username)
        @@trac_db_username = username
      end
      
      def self.set_trac_db_password(password)
        @@trac_db_password = password
      end
      
      def self.set_trac_db_schema(schema)
        @@trac_db_schema = schema
      end

      mattr_reader :trac_directory, :trac_adapter, :trac_db_host, :trac_db_port, :trac_db_name, :trac_db_schema, :trac_db_username, :trac_db_password
      
      def self.trac_db_path; "#{trac_directory}/db/trac.db" end
      def self.trac_attachments_directory; "#{trac_directory}/attachments" end
      
      def self.target_project_identifier(identifier)
        project = Project.find_by_identifier(identifier)        
        if !project
          # create the target project
          project = Project.new :name => identifier.humanize,
                                :description => ''
          project.identifier = identifier
          raise "Unable to create a project with identifier '#{identifier}'!" unless project.save
          # enable issues and wiki for the created project
          project.enabled_module_names = ['issue_tracking', 'wiki']
        else
          puts
          puts "This project already exists in your Redmine database."
          print "Are you sure you want to append data to this project ? [Y/n] "
          exit if STDIN.gets.match(/^n$/i)  
        end      
        
        TRACKER_MAPPING.values.uniq.each do |tracker|
          project.trackers << tracker unless project.trackers.include?(tracker)          
        end
        @target_project = project
      end
      
      def self.target_project_name(name)
        @target_project.name = name
        @target_project.save!
      end
      
      def self.connection_params
        if %w(sqlite sqlite3).include?(trac_adapter)
          {:adapter => trac_adapter, 
           :database => trac_db_path}
        else
          {:adapter => trac_adapter,
           :database => trac_db_name,
           :host => trac_db_host,
           :port => trac_db_port,
           :username => trac_db_username,
           :password => trac_db_password,
           :schema_search_path => trac_db_schema
          }
        end
      end
      
      def self.establish_connection
        constants.each do |const|
          klass = const_get(const)
          next unless klass.respond_to? 'establish_connection'
          klass.establish_connection connection_params
        end
      end
      
    private
      def self.encode(text)
        @ic.iconv text
      rescue
        text
      end
    end
    
    puts
    if Redmine::DefaultData::Loader.no_data?
      puts "Redmine configuration need to be loaded before importing data."
      puts "Please, run this first:"
      puts
      puts "  rake redmine:load_default_data RAILS_ENV=\"#{ENV['RAILS_ENV']}\""
      exit
    end
    
    puts "WARNING: a new project will be added to Redmine during this process."
    #print "Are you sure you want to continue ? [y/N] "
    #break unless STDIN.gets.match(/^y$/i)  
    puts

    def prompt(text, options = {}, &block)
      default = options[:default] || ''
      while true
        print "#{text} [#{default}]: "
        value = STDIN.gets.chomp!
        value = default if value.blank?
        break if yield value
      end
    end
    
    DEFAULT_PORTS = {'mysql' => 3306, 'postgresql' => 5432}
    puts "Usage: rake redmine:redmine:migrate_from_trac_08_4 [trac project name] [redmine project id] [redmine project name]" if ARGV.length < 3
    
    prompt('Trac directory', :default => '/opt/tracker/%s' % ARGV[1]) {|directory| TracMigrate.set_trac_directory directory.strip}
    prompt('Trac database adapter (sqlite, sqlite3, mysql, postgresql)', :default => 'sqlite3') {|adapter| TracMigrate.set_trac_adapter adapter}
    unless %w(sqlite sqlite3).include?(TracMigrate.trac_adapter)
      prompt('Trac database host', :default => 'localhost') {|host| TracMigrate.set_trac_db_host host}
      prompt('Trac database port', :default => DEFAULT_PORTS[TracMigrate.trac_adapter]) {|port| TracMigrate.set_trac_db_port port}
      prompt('Trac database name') {|name| TracMigrate.set_trac_db_name name}
      prompt('Trac database schema', :default => 'public') {|schema| TracMigrate.set_trac_db_schema schema}
      prompt('Trac database username') {|username| TracMigrate.set_trac_db_username username}
      prompt('Trac database password') {|password| TracMigrate.set_trac_db_password password}
    end
    prompt('Trac database encoding', :default => 'UTF-8') {|encoding| TracMigrate.encoding encoding}
    prompt('Target project identifier', :default => ARGV[2]) {|identifier| TracMigrate.target_project_identifier identifier}
    prompt('Target project name', :default => ARGV[3]) {|name| TracMigrate.target_project_name name}
    puts
    
    TracMigrate.migrate
  end
end
