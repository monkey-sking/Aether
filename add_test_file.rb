require 'xcodeproj'
require 'fileutils'

project_path = '/Volumes/SSD/Projects/Aether/Aether.xcodeproj'
project = Xcodeproj::Project.open(project_path)

test_target = project.targets.find { |t| t.name == 'AetherTests' }

# Create AetherTests group if not exists
test_group = project.main_group.find_subpath('AetherTests', true)
test_group.set_source_tree('<group>')
test_group.set_path('AetherTests')

files_to_add = [
  'VoiceCommandRouterTests.swift'
]

files_to_add.each do |file_name|
  file_path = File.join('/Volumes/SSD/Projects/Aether/AetherTests', file_name)
  # Check if reference already exists
  unless test_group.files.any? { |f| f.path == file_name || (f.path && f.path.end_with?(file_name)) }
    file_ref = test_group.new_file(file_path)
    test_target.source_build_phase.add_file_reference(file_ref)
    puts "Added #{file_name} to test target"
  else
    puts "#{file_name} already in test project"
  end
end

project.save
puts "Project saved."
