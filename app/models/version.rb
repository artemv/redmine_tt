# redMine - project management software
# Copyright (C) 2006  Jean-Philippe Lang
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

class Version < ActiveRecord::Base
  before_destroy :check_integrity
  belongs_to :project
  has_many :fixed_issues, :class_name => 'Issue', :foreign_key => 'fixed_version_id'
  has_many :attachments, :as => :container, :dependent => :destroy

  validates_presence_of :name
  validates_uniqueness_of :name, :scope => [:project_id]
  validates_length_of :name, :maximum => 100
  validates_format_of :effective_date, :with => /^\d{4}-\d{2}-\d{2}$/, :message => :activerecord_error_not_a_date, :allow_nil => true
  
  def start_date
    effective_date
  end
  
  def due_date
    effective_date
  end
  
  # Returns the total estimated time for this version
  def estimated_hours
    @estimated_hours ||= fixed_issues.sum(:estimated_hours).to_f
  end
  
  # Returns the total reported time for this version
  def spent_hours
    @spent_hours ||= TimeEntry.sum(:hours, :include => :issue, :conditions => ["#{Issue.table_name}.fixed_version_id = ?", id]).to_f
  end

  
  def calc_remaining_and_total_time
    @remaining_hours = 0
    @total_hours = 0
    get_grouped_metrics(:category).to_a.map{|item| item[1]}.map {|item| item[:time]}.each do |times| 
      @remaining_hours += times[:remaining]
      @total_hours += times[:total]
    end
  end
  
  def remaining_hours
    return @remaining_hours if @remaining_hours
    calc_remaining_and_total_time
    @remaining_hours    
  end
  
  def total_hours
    return @total_hours if @total_hours
    calc_remaining_and_total_time
    @total_hours
  end
  
  # Returns true if the version is completed: due date reached and no open issues
  def completed?
    effective_date && (effective_date <= Date.today) && (open_issues_count == 0)
  end
  
  def completed_pourcent
    if fixed_issues.count == 0
      0
    elsif open_issues_count == 0
      100
    else
      (closed_issues_count * 100 + Issue.sum('done_ratio', :include => 'status', :conditions => ["fixed_version_id = ? AND is_closed = ?", id, false]).to_f) / fixed_issues.count
    end
  end
  
  def closed_pourcent
    if fixed_issues.count == 0
      0
    else
      closed_issues_count * 100.0 / fixed_issues.count
    end
  end
  
  # Returns true if the version is overdue: due date reached and some open issues
  def overdue?
    effective_date && (effective_date < Date.today) && (open_issues_count > 0)
  end
  
  def open_issues_count
    @open_issues_count ||= Issue.count(:all, :conditions => ["fixed_version_id = ? AND is_closed = ?", self.id, false], :include => :status)
  end

  def closed_issues_count
    @closed_issues_count ||= Issue.count(:all, :conditions => ["fixed_version_id = ? AND is_closed = ?", self.id, true], :include => :status)
  end
  
  def wiki_page
    if project.wiki && !wiki_page_title.blank?
      @wiki_page ||= project.wiki.find_page(wiki_page_title)
    end
    @wiki_page
  end
  
  def to_s; name end
  
  # Versions are sorted by effective_date and name
  # Those with no effective_date are at the end, sorted by name
  def <=>(version)
    if self.effective_date
      version.effective_date ? (self.effective_date == version.effective_date ? self.name <=> version.name : self.effective_date <=> version.effective_date) : -1
    else
      version.effective_date ? 1 : (self.name <=> version.name)
    end
  end
  
  def get_grouped_metrics(criteria)
    condition = issues_version_condition
    
    issues = Issue.find(:all, :include => [:status, criteria], 
      :conditions => condition)
    
    spent_times = {}
    TimeEntry.sum(:hours, :group => :issue_id, :include => :issue,
        :conditions => condition).each do |issue_id, hours| 
        
      spent_times[issue_id] = hours
    end

    categories_metrics = {}
    issues.each do |issue|
      category = issue.send(criteria)
      categories_metrics[category] ||= {}
      categories_metrics[category][:time] ||= {:estimated => 0, 
        :spent => 0, :remaining => 0, :total => 0}
      metrics = categories_metrics[category][:time]
      
      estimated = issue.estimated_hours || 0
      metrics[:estimated] += estimated
      spent = spent_times[issue.id] || 0
      metrics[:spent] += spent
      remaining = issue.closed? ? 0 : estimated - spent
      remaining = 0 if remaining < 0
      metrics[:remaining] += remaining
      metrics[:total] += (remaining + spent)
      
      categories_metrics[category][:count] ||= {:open => 0, :closed => 0, :total => 0}
      metrics = categories_metrics[category][:count]
      metrics[:total] += 1
      if issue.closed?
        metrics[:closed] += 1 
      else
        metrics[:open] += 1 
      end
    end
    categories_metrics
  end
  
  def issues_version_condition
    ["#{Issue.table_name}.fixed_version_id = ?", id]
  end

  private
  def check_integrity
    raise "Can't delete version" if self.fixed_issues.find(:first)
  end
end
