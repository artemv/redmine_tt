# redMine - project management software
# Copyright (C) 2006-2008  Jean-Philippe Lang
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

class TimeEntry < ActiveRecord::Base
  # could have used polymorphic association
  # project association here allows easy loading of time entries at project level with one database trip
  belongs_to :project
  belongs_to :issue
  belongs_to :user
  belongs_to :activity, :class_name => 'Enumeration', :foreign_key => :activity_id
  
  attr_protected :project_id, :user_id, :tyear, :tmonth, :tweek

  acts_as_customizable
  title_proc = Proc.new do |entry|    
    hours = entry.hours ? lwr(:label_f_hour, entry.hours) : "[#{l(:text_in_progress)}]"
    "#{entry.user}: #{hours} (#{(entry.issue || entry.project).event_title})"
  end
  
  acts_as_event :title => title_proc,
                :url => Proc.new {|entry| {:controller => 'timelog', :action => 'details', :project_id => entry.project}},
                :author => :user,
                :description => :comments
  
  validates_presence_of :user_id, :activity_id, :project_id, :spent_on
  validates_numericality_of :hours, :allow_nil => true
  validates_length_of :comments, :maximum => 255, :allow_nil => true

  MAX_START_END_TIME_DISTANCE = 15.hours
  TIME_WARNING_PRECISION = 2.minutes
  
  def after_initialize
    if new_record? && self.activity.nil?
      if default_activity = Enumeration.default('ACTI')
        self.activity_id = default_activity.id
      end
    end
  end
  
  def before_validation
    self.project = issue.project if issue && project.nil?
  end
  
  def validate
    errors.add :hours, :activerecord_error_invalid if hours && 
      (hours >= 1000 || hours < 0)
    
    if !start_time && !hours
      #rather verbose, but l() always translate to English here for some reason
      errors.add :hours, ll(User.current.language, 
          :activerecord_error_field_must_be_set_if_other_is_not, 
          ll(User.current.language, :field_start_time))

      errors.add :start_time, ll(User.current.language, 
          :activerecord_error_field_must_be_set_if_other_is_not, 
          ll(User.current.language, :field_hours))
    end
    
    if start_time && spent_on && start_time.to_date != spent_on
      errors.add :start_time, ll(User.current.language, 
          :error_must_be_same_day_with_spent_on)
    end
    
    if start_time && end_time
      
      if !hours && (end_time - start_time) > MAX_START_END_TIME_DISTANCE
        errors.add :end_time, ll(User.current.language, 
            :error_max_distance_between_start_and_end_time, 
            MAX_START_END_TIME_DISTANCE / 3600)
      end
      
      if start_time >= end_time
        errors.add :end_time, ll(User.current.language, 
            :error_end_time_must_be_after_start_time)
      end
    end

    errors.add :project_id, :activerecord_error_invalid if project.nil?
    errors.add :issue_id, :activerecord_error_invalid if (issue_id && !issue) || (issue && project!=issue.project)
  end
  
  def hours=(h)
    write_attribute :hours, (h.is_a?(String) ? h.to_hours : h)
  end
  
  # tyear, tmonth, tweek assigned where setting spent_on attributes
  # these attributes make time aggregations easier
  def spent_on=(date)
    super
    self.tyear = spent_on ? spent_on.year : nil
    self.tmonth = spent_on ? spent_on.month : nil
    self.tweek = spent_on ? Date.civil(spent_on.year, spent_on.month, spent_on.day).cweek : nil
  end
  
  # Returns true if the time entry can be edited by usr, otherwise false
  def editable_by?(usr)
    (usr == user && usr.allowed_to?(:edit_own_time_entries, project)) || usr.allowed_to?(:edit_time_entries, project)
  end
  
  def self.visible_by(usr)
    with_scope(:find => { :conditions => Project.allowed_to_condition(usr, :view_time_entries) }) do
      yield
    end
  end
  
  def before_save
    if !hours && start_time && end_time
      self.hours = (end_time - start_time) / 3600
    end
  end
  
  def find_intersecting_entries
    params = {:start_time => start_time, :end_time => end_time, :id => id}
    
    self.class.find_all_by_user_id(user_id, :conditions => 
        ["(" + 
          #this entry's start time or end time is between other's start_time and end_time
          "start_time < :start_time and :start_time < end_time OR " + 
          "start_time < :end_time and :end_time < end_time OR " + 
          #other's entry's start time or end time is between this entry's start_time and end_time
          "start_time > :start_time and start_time < :end_time OR " + 
          "end_time > :start_time and end_time < :end_time" +
          ")" + 
          "and id <> :id", params])
  end
  
  def distance_differ_from_hours?
    return if !end_time || !start_time || !hours
    distance = end_time - start_time
    if (distance - hours.hours).abs >= TIME_WARNING_PRECISION
      {:distance => distance/3600, :hours => hours}
    end    
  end
  
  def empty?
    result = !hours && !start_time && !end_time && comments.blank?
    #puts "hours = %s, activity_id = %s, start_time = %s, end_time = %s, comments = %s" % [hours, activity_id, start_time, end_time, comments].map(&:inspect)
    result
  end
end
