require 'xcodeproj'
require 'fileutils'

project_path = '/Volumes/SSD/Projects/Aether/Aether.xcodeproj'
project = Xcodeproj::Project.open(project_path)

test_target_name = 'AetherTests'
if project.targets.find { |t| t.name == test_target_name }
  puts "Target #{test_target_name} already exists."
  exit 0
end

main_target = project.targets.find { |t| t.name == 'Aether' }
if main_target.nil?
  puts "Main target 'Aether' not found."
  exit 1
end

# Create test target
test_target = project.new_target(:unit_test_bundle, test_target_name, :macos)

# Build settings
test_target.build_configurations.each do |config|
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/Aether.app/Contents/MacOS/Aether'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.7fei.AetherTests'
  config.build_settings['INFOPLIST_FILE'] = 'AetherTests/Info.plist'
  config.build_settings['SWIFT_VERSION'] = '5.0'
end

# Add dependencies
project.root_object.project_references.each do |ref|
  # handled by standard
end
test_target.add_dependency(main_target)

# Create files and groups
tests_group = project.main_group.find_subpath(File.join(test_target_name), true)
tests_group.set_source_tree('<group>')
tests_group.set_path(test_target_name)

tests_dir = File.join(File.dirname(project_path), test_target_name)
FileUtils.mkdir_p(tests_dir)

# Create Info.plist
info_plist_path = File.join(tests_dir, 'Info.plist')
File.write(info_plist_path, <<-PLIST)
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
</dict>
</plist>
PLIST

# Create a sample test
sample_test_path = File.join(tests_dir, 'AetherTests.swift')
File.write(sample_test_path, <<-SWIFT)
import XCTest
@testable import Aether

class AetherTests: XCTestCase {
    func testExample() throws {
        XCTAssertTrue(true)
    }
}
SWIFT

# Add references to project
tests_group.new_file('Info.plist')
sample_test_ref = tests_group.new_file('AetherTests.swift')
test_target.add_file_references([sample_test_ref])

project.save

# Now add it to the scheme
scheme_path = File.join(project_path, 'xcshareddata', 'xcschemes', 'Aether.xcscheme')
if File.exist?(scheme_path)
  scheme = Xcodeproj::XCScheme.new(scheme_path)
  
  test_action = scheme.test_action
  # Only add if not already there
  unless test_action.testables.any? { |t| t.buildable_references.any? { |b| b.target_name == test_target_name } }
    testable_ref = Xcodeproj::XCScheme::TestAction::TestableReference.new(test_target)
    test_action.add_testable(testable_ref)
    scheme.save!
  end
else
  puts "Scheme not found at #{scheme_path}, creating default one..."
end

puts "Success."
