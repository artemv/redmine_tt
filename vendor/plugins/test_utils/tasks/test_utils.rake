##
# based on http://nubyonrails.com/articles/foscon-and-living-dangerously-with-rake
# Run a single test (or group of tests started with given string) in Rails.
#
#   rake blogs-list (or f_blogs-list)
#   => Runs test_list for BlogsController (functional test; use f_blogs-list to force it if unit test found)
#
#   rake blog-create (or u_blog-create)
#   => Runs test_create for BlogTest (unit test; use u_blog-create to force it if functional test found))

#test file will be matched in the order of this array items 
TEST_TYPES = [
    ['u_', "unit/[file_name]_test.rb"],
    ['f_', "functional/[file_name]_controller_test.rb"],
    ['i_', "integration/[file_name]_test.rb"],
    ['l_', "long/[file_name]_test.rb"],
]

rule "" do |t|
  all_flags = TEST_TYPES.map { |item| item[0] }
  if Regexp.new("(#{all_flags.join '|'}|)(.*)\\-([^.]+)$").match(t.name)
    flag = $1
    file_name = $2
    test_name = $3

    path_getter = lambda { |type_info| type_info[1].gsub '[file_name]', file_name}
    file_path = nil
    TEST_TYPES.each do |type_info|
      my_file_path = path_getter.call(type_info)
      if flag == type_info[0]
        type_info[1].match /((.+)\/)/
        type = $2
        puts "forced #{type} test"
        file_path = my_file_path
        break
      end
    end

    if file_path && !File.exist?("test/#{file_path}")
      raise "No file found for #{file_path}"
    end

    if !file_path
      TEST_TYPES.each do |type_info|
        my_file_path = path_getter.call(type_info)
        if File.exist? "test/#{my_file_path}"
          puts "found #{my_file_path}"
          file_path = my_file_path
          break
        end
      end
    end

    if !file_path
      raise "No file found for #{file_name}"
    end

		begin
      sh "ruby -Ilib:test test/#{file_path} -n /^test_#{test_name}/"
    rescue Exception => e
      #no logger here, oops!
    	#log.debug "error executing tests: #{e.inspect}"
      puts "error executing tests: #{e.inspect}"
    end
  end
end
