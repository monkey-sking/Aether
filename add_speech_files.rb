require 'xcodeproj'
require 'fileutils'

project_path = '/Volumes/SSD/Projects/Aether/Aether.xcodeproj'
project = Xcodeproj::Project.open(project_path)

main_target = project.targets.find { |t| t.name == 'Aether' }

target_group = nil
project.main_group.recursive_children.each do |node|
  # If it's a file reference and its path contains SpeechManager.swift
  if node.is_a?(Xcodeproj::Project::Object::PBXFileReference) && node.path && node.path.end_with?('SpeechManager.swift')
    target_group = node.parent
    break
  end
end

if target_group.nil?
  puts "Group for SpeechManager.swift not found. Fallback to main group."
  target_group = project.main_group
end

speech_group = target_group.find_subpath('Speech', true)
speech_group.set_source_tree('<group>')
# Xcode group path could be empty if it maps to current dir or 'Speech' if we want it to map to the Speech directory
speech_group.set_path('Apps/AetherCore/Speech') if target_group == project.main_group
speech_group.set_path('Speech') unless target_group == project.main_group

files_to_add = [
  'VoiceCommandRouter.swift',
  'LLMProviders.swift',
  'TextInjector.swift',
  'AirPodsDetector.swift'
]

files_to_add.each do |file_name|
  file_path = File.join('/Volumes/SSD/Projects/Aether/Apps/AetherCore/Speech', file_name)
  
  unless speech_group.files.any? { |f| f.path == file_name || (f.path && f.path.end_with?(file_name)) }
    file_ref = speech_group.new_file(file_path)
    main_target.source_build_phase.add_file_reference(file_ref)
    puts "Added #{file_name} to target"
  else
    puts "#{file_name} already in project"
  end
end

project.save
puts "Project saved."
