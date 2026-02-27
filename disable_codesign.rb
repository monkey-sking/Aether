require 'xcodeproj'

project_path = '/Volumes/SSD/Projects/Aether/Aether.xcodeproj'
project = Xcodeproj::Project.open(project_path)

test_target = project.targets.find { |t| t.name == 'AetherTests' }
if test_target
  test_target.build_configurations.each do |config|
    config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    config.build_settings['CODE_SIGN_IDENTITY'] = ''
  end
  project.save
  puts "Disabled codesign for AetherTests"
else
  puts "Target not found"
end
