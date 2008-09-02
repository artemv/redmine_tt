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

module VersionsHelper

  STATUS_BY_CRITERIAS = %w(category tracker priority author assigned_to)
  
  def render_issue_status_by(version, criteria)
    criteria ||= 'category'
    raise 'Unknown criteria' unless STATUS_BY_CRITERIAS.include?(criteria)
    
    #sort them alphabetically by category name
    metrics = version.get_grouped_metrics(criteria).to_a.sort {|x, y| x[0].to_s <=> y[0].to_s} 
    max = {}
    
    [{:count => :total}, {:time => :total}].each do |metric_info| 
      metrics_group, total_metric = metric_info.to_a.flatten
      max[metrics_group] = metrics.map{|item| item[1]}.map {|item| item[metrics_group]}.map {|item| item[total_metric]}.max
      max[metrics_group] = 1 if max[metrics_group] == 0
    end
    
    render :partial => 'issue_counts', :locals => {:version => version, 
      :criteria => criteria, :grouped_metrics => metrics, :max => max, 
      :spent_time_allowed => User.current.allowed_to?(:view_time_entries, @project), 
      }
  end

  def time_progress(time_info)  
    logger.debug "time_info[:spent] = #{time_info[:spent].inspect}"
    logger.debug "time_info[:total] = #{time_info[:total].inspect}"
    if (time_info[:total] != 0)
      time_progress = time_info[:spent].to_f / time_info[:total]
    else
      time_progress = 0 #no total also means there's no spent time
    end    
    time_progress
  end
  
  def status_by_options_for_select(value)
    options_for_select(STATUS_BY_CRITERIAS.collect {|criteria| [l("field_#{criteria}".to_sym), criteria]}, value)
  end
end
