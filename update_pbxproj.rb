require 'fileutils'
require 'xcodeproj'

project_path = '/Users/tenyi/Projects/VoiceInput/VoiceInput.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Extract correct target
target = project.targets.find { |t| t.name == 'VoiceInput' } || project.targets.first

# Check or create group for Settings/Views
main_group = project.main_group.find_subpath('VoiceInput', false)
settings_group = main_group.find_subpath('Settings', true)
views_group = settings_group.find_subpath('Views', true)

# Ensure physically it reflects
views_group.set_source_tree('<group>')
views_group.set_path('Settings/Views')

files_to_add = [
  'GeneralSettingsView.swift',
  'TranscriptionSettingsView.swift',
  'ModelSettingsView.swift',
  'LLMSettingsView.swift',
  'HistorySettingsView.swift',
  'CustomProviderSheets.swift'
]

files_to_add.each do |filename|
  # Only add if not already in the group
  existing = views_group.files.find { |f| f.path == filename }
  unless existing
    ref = views_group.new_file(filename)
    target.source_build_phase.add_file_reference(ref, true)
  end
end

project.save
puts "Xcode project updated successfully"
