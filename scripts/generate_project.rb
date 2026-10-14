#!/usr/bin/env ruby
# Regenerates Walkou.xcodeproj from the folders on disk.
#
#   gem install xcodeproj
#   ruby scripts/generate_project.rb
#
# Run it after adding or removing Swift files, then reopen the project in Xcode.

require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'Walkou.xcodeproj')
DEPLOYMENT_TARGET = '17.0'
BUNDLE_ID = 'com.walkou.app'

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.attributes['LastSwiftUpdateCheck'] = '1600'
project.root_object.attributes['LastUpgradeCheck'] = '1600'

# Adds every file under `dir` to `group`, mirroring sub-folders. Returns the file references.
def add_tree(project, group, dir)
  refs = []
  Dir.children(dir).sort.each do |name|
    next if name.start_with?('.')
    path = File.join(dir, name)
    if File.directory?(path) && !name.end_with?('.xcassets')
      sub = group.new_group(name, name)
      refs.concat(add_tree(project, sub, path))
    else
      refs << group.new_reference(name)
    end
  end
  refs
end

# App target
app = project.new_target(:application, 'Walkou', :ios, DEPLOYMENT_TARGET)
app_group = project.main_group.new_group('Walkou', 'Walkou')
app_refs = add_tree(project, app_group, File.join(ROOT, 'Walkou'))

app_refs.each do |ref|
  case File.extname(ref.path)
  when '.swift'
    app.source_build_phase.add_file_reference(ref)
  when '.xcassets', '.wav'
    app.resources_build_phase.add_file_reference(ref)
  end
end

app.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_NAME'] = 'Walkou'
  s['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  s['INFOPLIST_FILE'] = 'Walkou/Resources/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  # Free Apple ID: no HealthKit. With a paid account switch to Walkou/Resources/WalkouHealthKit.entitlements.
  s['CODE_SIGN_ENTITLEMENTS'] = 'Walkou/Resources/Walkou.entitlements'
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['DEVELOPMENT_TEAM'] = ''
  s['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  s['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  s['TARGETED_DEVICE_FAMILY'] = '1'
  s['SWIFT_VERSION'] = '5.0'
  s['MARKETING_VERSION'] = '1.0'
  s['CURRENT_PROJECT_VERSION'] = '1'
  s['ENABLE_PREVIEWS'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks']
  s['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  s['ENABLE_TESTABILITY'] = 'YES' if config.name == 'Debug'
end

# Unit tests
tests = project.new_target(:unit_test_bundle, 'WalkouTests', :ios, DEPLOYMENT_TARGET)
tests_group = project.main_group.new_group('WalkouTests', 'WalkouTests')
add_tree(project, tests_group, File.join(ROOT, 'WalkouTests')).each do |ref|
  tests.source_build_phase.add_file_reference(ref) if File.extname(ref.path) == '.swift'
end
tests.add_dependency(app)
tests.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_NAME'] = 'WalkouTests'
  s['PRODUCT_BUNDLE_IDENTIFIER'] = "#{BUNDLE_ID}.tests"
  s['GENERATE_INFOPLIST_FILE'] = 'YES'
  s['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/Walkou.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Walkou'
  s['BUNDLE_LOADER'] = '$(TEST_HOST)'
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  s['TARGETED_DEVICE_FAMILY'] = '1'
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['DEVELOPMENT_TEAM'] = ''
end

# xcodeproj links Foundation.framework through a hard-coded SDK path; Swift auto-links system
# frameworks anyway, so drop it to keep the project independent of the installed SDK version.
[app, tests].each do |target|
  target.frameworks_build_phase.files.to_a.each do |build_file|
    ref = build_file.file_ref
    build_file.remove_from_project
    ref.remove_from_project if ref && ref.build_files.empty?
  end
end
project.frameworks_group.children.to_a.each do |child|
  child.remove_from_project if child.isa == 'PBXGroup' && child.children.empty?
end

# Supporting files that are not built but nice to see in Xcode
project.main_group.new_reference('README.md') if File.exist?(File.join(ROOT, 'README.md'))

project.sort(groups_position: :above)
project.save

# Shared scheme with tests
scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app, tests, launch_target: true)
scheme.save_as(PROJECT_PATH, 'Walkou', true)

puts "Generated #{PROJECT_PATH}"
