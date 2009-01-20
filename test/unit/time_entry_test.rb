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

class TimeEntryTest < Test::Unit::TestCase
  fixtures :issues, :projects, :users, :time_entries

  def setup
    User.current.language = 'en'
  end
  
  def test_hours_format
    assertions = { "2"      => 2.0,
                   "21.1"   => 21.1,
                   "2,1"    => 2.1,
                   "1,5h"   => 1.5,
                   "7:12"   => 7.2,
                   "10h"    => 10.0,
                   "10 h"   => 10.0,
                   "45m"    => 0.75,
                   "45 m"   => 0.75,
                   "3h15"   => 3.25,
                   "3h 15"  => 3.25,
                   "3 h 15"   => 3.25,
                   "3 h 15m"  => 3.25,
                   "3 h 15 m" => 3.25,
                   "3 hours"  => 3.0,
                   "12min"    => 0.2,
                  }
    
    assertions.each do |k, v|
      t = TimeEntry.new(:hours => k)
      assert_equal v, t.hours, "Converting #{k} failed:"
    end
  end
  
  def test_start_time_must_be_set_if_hours_are_not_and_reverse
    entry = TimeEntry.new
    assert_error_on(entry, :start_time)
    assert_error_on(entry, :hours)    
  end

  def test_start_time_can_be_absent_if_hours_are_set_and_reverse
    entry = TimeEntry.new :hours => 1
    entry.valid?
    assert_no_error_on(entry, :start_time)
    entry = TimeEntry.new :start_time => Time.now
    entry.valid?
    assert_no_error_on(entry, :hours)
  end

  def successful_params
    {:spent_on => '2008-07-13', :issue_id => 1, :user => users(:users_004), 
      :activity_id => Enumeration.get_values('ACTI').first}
  end
  
  def test_hours_not_calculated_if_set_explicitly
    #I worked on this time to time during the day, and it was 1 hour in sum
    entry = TimeEntry.new successful_params.merge(:hours => 1, 
      :start_time => '2008-07-13 10:56', :end_time => '2008-07-14 10:56')
      
    entry.save!    
    assert_equal 1, entry.hours
  end

  {['10:56', '11:56'] => 1, ['10:56', '11:26'] => 0.5, 
      ['10:56', '10:57'] => 0.0167,
      ['2008-07-13 23:50', '2008-07-14 00:20'] => 0.5}.each do |range, hours|
    
    define_method "test_hours_calculated_#{range[0]}_to_#{range[1]}" do
      
      #add default day if not specified
      range = range.map {|time| time['-'] ? time : '2008-07-13 ' + time} 
      
      entry = TimeEntry.new successful_params.merge(:hours => nil, 
        :start_time => range[0], :end_time => range[1])
      entry.save!    
      assert_in_delta hours, entry.hours, 0.0001
    end
  end
  
  def assert_intersects(source, dest)
    intersecting = time_entries(source).find_intersecting_entries
    
    assert !intersecting.empty?, 
      "there should be intersecting entries for #{source.inspect}"
    
    assert intersecting.map {|e| e.id}.
        include?(time_entries(dest).id), 
        "#{source.inspect} should intersect with #{dest.inspect}"
    
    intersecting
  end
  
  def test_find_intersecting_entries_for_incomplete
    assert_intersects(:time_entry_in_progress, :intersecting_time_entry)
  end

  def test_find_intersecting_entries_for_complete_doesnt_find_itself
    intersecting = assert_intersects(:intersecting_time_entry, 
      :time_entry_in_progress)

    assert !intersecting.map {|e| e.id}.include?(
      time_entries(:intersecting_time_entry)), 'time entry\'s ' + 
      'intersecting entries shouldn\'t include itself'
  end

  def test_find_intersecting_entries_for_big
    assert_intersects(:big_intersecting_time_entry, :time_entry_in_progress)
    assert_intersects(:big_intersecting_time_entry, :intersecting_time_entry)
  end

  def test_start_time_must_be_same_date_as_spent_on
    entry = TimeEntry.new(successful_params)
    entry.spent_on = Date.today
    entry.start_time = Time.now - 1.day
    assert_error_on(entry, :start_time)
    entry.start_time = Time.now + 1.day
    assert_error_on(entry, :start_time)
    entry.start_time = Time.now
    assert_no_errors(entry, :validate => true)
  end

  def test_distance_between_start_and_end_time_is_reasonable
    entry = TimeEntry.new(successful_params)
    entry.start_time = Time.utc(2008, 'Oct', 22, 15, 50)
    entry.spent_on = entry.start_time.to_date
    
    entry.end_time = entry.start_time + 
      TimeEntry::MAX_START_END_TIME_DISTANCE + 1.minute
    
    assert_error_on(entry, :end_time)
    entry.end_time -= 1.minute
    assert_no_errors(entry, :validate => true)
  end

  def test_end_time_must_be_after_start_time
    entry = TimeEntry.new(successful_params)
    entry.start_time = Time.utc(2008, 'Oct', 22, 15, 50)
    entry.spent_on = entry.start_time.to_date
    
    entry.end_time = entry.start_time - 1.minute
    
    assert_error_on(entry, :end_time)
    entry.end_time = entry.start_time + 1.minute
    assert_no_errors(entry, :validate => true)
  end

end
