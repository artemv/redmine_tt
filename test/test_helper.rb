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

ENV["RAILS_ENV"] ||= "test"
require File.expand_path(File.dirname(__FILE__) + "/../config/environment")
require 'test_help'
require File.expand_path(File.dirname(__FILE__) + '/helper_testcase')

class Test::Unit::TestCase
  # Transactional fixtures accelerate your tests by wrapping each test method
  # in a transaction that's rolled back on completion.  This ensures that the
  # test database remains unchanged so your fixtures don't have to be reloaded
  # between every test method.  Fewer database queries means faster tests.
  #
  # Read Mike Clark's excellent walkthrough at
  #   http://clarkware.com/cgi/blosxom/2005/10/24#Rails10FastTesting
  #
  # Every Active Record database supports transactions except MyISAM tables
  # in MySQL.  Turn off transactional fixtures in this case; however, if you
  # don't care one way or the other, switching from MyISAM to InnoDB tables
  # is recommended.
  self.use_transactional_fixtures = true

  # Instantiated fixtures are slow, but give you @david where otherwise you
  # would need people(:david).  If you don't want to migrate your existing
  # test cases which use the @david style and don't mind the speed hit (each
  # instantiated fixtures translates to a database query per test method),
  # then set this back to true.
  self.use_instantiated_fixtures  = false

  # Add more helper methods to be used by all tests here...
  
  def log_user(login, password)
    get "/account/login"
    assert_equal nil, session[:user_id]
    assert_response :success
    assert_template "account/login"
    post "/account/login", :username => login, :password => password
    assert_redirected_to "my/page"
    assert_equal login, User.find(session[:user_id]).login
  end
  
  def test_uploaded_file(name, mime)
    ActionController::TestUploadedFile.new(Test::Unit::TestCase.fixture_path + "/files/#{name}", mime)
  end
  
  # Use a temporary directory for attachment related tests
  def set_tmp_attachments_directory
    Dir.mkdir "#{RAILS_ROOT}/tmp/test" unless File.directory?("#{RAILS_ROOT}/tmp/test")
    Dir.mkdir "#{RAILS_ROOT}/tmp/test/attachments" unless File.directory?("#{RAILS_ROOT}/tmp/test/attachments")
    Attachment.storage_path = "#{RAILS_ROOT}/tmp/test/attachments"
  end

  def assert_error_on(object, field)
    object.valid?
    assert object.errors.on(field), "expected error on #{field} attribute"
  end

  def assert_no_error_on(object, field)
    object.valid?
    assert !object.errors.on(field), "expected no error on #{field} attribute"
  end

  def assert_no_errors(object, options = {})
    object.valid? if options[:validate]
    assert_equal [], object.errors.full_messages
  end
end
