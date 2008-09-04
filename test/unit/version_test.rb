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

require File.dirname(__FILE__) + '/../test_helper'

class VersionTest < Test::Unit::TestCase
  fixtures :all

  def verify_counts(count_metrics, undone, done)
    assert_equal undone + done, count_metrics[:total]
    assert_equal undone, count_metrics[:undone]
    assert_equal done, count_metrics[:done]    
  end
  
  def test_get_grouped_metrics_count
    version = versions(:versions_002)
    grouped_metrics = version.get_grouped_metrics(:tracker)
    verify_counts(grouped_metrics[trackers(:trackers_001)][:count], 2, 1)
    verify_counts(grouped_metrics[trackers(:trackers_002)][:count], 1, 0)
  end
  
  def test_get_grouped_metrics_time
    version = versions(:versions_002)
    grouped_metrics = version.get_grouped_metrics(:tracker)
    time_metrics = grouped_metrics[trackers(:trackers_001)][:time]
    
    estimated = [:issues_001, :issues_003, :issues_007].inject(0) do |prev, current| 
      issues(current).estimated_hours + prev
    end
    
    assert_equal estimated, time_metrics[:estimated]

    spent = [:issues_001, :issues_003].inject(0) do |prev, current| 
      issues(current).spent_hours + prev
    end    
    assert_equal spent, time_metrics[:spent]

    i3 = issues(:issues_003)    
    #issue 1 is not counted because it spent more than estimated; 
    #  issue 7 not counted because because it's closed
    remaining = i3.estimated_hours - i3.spent_hours 
    assert_equal remaining, time_metrics[:remaining]
    
    assert_equal spent + remaining, time_metrics[:total]
  end
  
end
