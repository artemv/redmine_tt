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

require File.dirname(__FILE__) + '/../test_helper'
require 'versions_controller'

# Re-raise errors caught by the controller.
class VersionsController; def rescue_action(e) raise e end; end

class VersionsControllerTest < Test::Unit::TestCase
  fixtures :projects, :versions, :issues, :users, :roles, :members, :enabled_modules, :issue_statuses, :trackers
  
  def setup
    @controller = VersionsController.new
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new
    User.current = nil
  end
  
  {:view_time_entries_allowed => {:version_id => 2},
      :view_time_entries_not_allowed => {:user_id => 3, :version_id => 4}
  }.each do |case_key, case_info|
    define_method "test_show_when_#{case_key}" do
      @request.session[:user_id] = case_info[:user_id] if case_info[:user_id]
      get :show, :id => case_info[:version_id]
      assert_response :success
      assert_template 'show'
      assert_not_nil assigns(:version)
      
      assert_tag :tag => 'h2', :content => Version.find(case_info[:version_id]).name
    end

    define_method "test_issue_status_by_when_#{case_key}" do
      @request.session[:user_id] = case_info[:user_id] if case_info[:user_id]
      xhr :get, :status_by, :id => case_info[:version_id]
      assert_response :success
      assert_template '_issue_counts'
    end
  end
  
  #specific bug was reproduced when there were no time records and all the issues were closed
  def test_issue_status_by_no_division_by_zero
    version = versions(:versions_003)
    user = users(:users_002)
    @request.session[:user_id] = user.id
    
    assert version.fixed_issues.size > 0, "version should have issues"
    project = version.project
    assert user.allowed_to?(:view_time_entries, project), "user should have :view_time_entries permission to project #{project.id}"
    version.fixed_issues.all? do |i| 
      assert_equal 0, i.spent_hours 
      assert !i.estimated_hours || i.estimated_hours == 0
      assert i.closed?
    end
    xhr :get, :status_by, :id => version.id
    assert_response :success
    assert_template '_issue_counts'
  end

  def test_get_edit
    @request.session[:user_id] = 2
    get :edit, :id => 2
    assert_response :success
    assert_template 'edit'
  end
  
  def test_post_edit
    @request.session[:user_id] = 2
    post :edit, :id => 2, 
                :version => { :name => 'New version name', 
                              :effective_date => Date.today.strftime("%Y-%m-%d")}
    assert_redirected_to 'projects/settings/ecookbook'
    version = Version.find(2)
    assert_equal 'New version name', version.name
    assert_equal Date.today, version.effective_date
  end

  def test_destroy
    @request.session[:user_id] = 2
    version = versions(:versions_001)
    assert version.fixed_issues.empty?, "version should have no issues"
    post :destroy, :id => version.id
    assert_redirected_to 'projects/settings/ecookbook'
    assert_nil Version.find_by_id(version.id)
  end
end
