#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
GENERATOR = File.join(__dir__, 'generate_project.rb')
MAC_ENTITLEMENT_PATHS = %w[
  Peekaboo/Peekaboo.entitlements
  Peekaboo/PeekabooDebug.entitlements
  Peekaboo/PeekabooLocal.entitlements
].freeze
MACH_LOOKUP_KEY = 'com.apple.security.temporary-exception.mach-lookup.global-name'

def generate(destination)
  success = system(
    RbConfig.ruby,
    GENERATOR,
    '--output',
    destination,
    out: File::NULL,
    err: File::NULL
  )
  abort 'Project generation failed' unless success
end

def digest(project_path)
  files = [
    File.join(project_path, 'project.pbxproj'),
    File.join(project_path, 'xcshareddata/xcschemes/Peekaboo.xcscheme'),
    File.join(project_path, 'xcshareddata/xcschemes/PeekabooMobile.xcscheme')
  ]
  Digest::SHA256.hexdigest(files.map { |path| File.binread(path) }.join)
end

def read_plist(relative_path)
  path = File.join(ROOT, relative_path)
  output, status = Open3.capture2('plutil', '-convert', 'json', '-o', '-', path)
  abort "Could not read #{relative_path}" unless status.success?

  JSON.parse(output)
end

def verify_no_temporary_mach_lookup_entitlements
  MAC_ENTITLEMENT_PATHS.each do |path|
    entitlements = read_plist(path)
    abort "#{path} must not contain #{MACH_LOOKUP_KEY}" if entitlements.key?(MACH_LOOKUP_KEY)
  end
end

def verify_mac_cloudkit_framework(project_path)
  project = Xcodeproj::Project.open(project_path)
  target = project.targets.find { |candidate| candidate.name == 'Peekaboo' }
  abort 'Generated project is missing the Peekaboo target' unless target

  frameworks = target.frameworks_build_phase.files_references.map do |reference|
    File.basename(reference.path.to_s)
  end
  abort 'Peekaboo target must link CloudKit.framework' unless frameworks.include?('CloudKit.framework')
end

Dir.mktmpdir('peekaboo-project-check') do |directory|
  project_path = File.join(directory, 'generated', 'Peekaboo.xcodeproj')
  generate(project_path)
  first_digest = digest(project_path)
  generate(project_path)
  abort 'Project generation is not repeatable' unless digest(project_path) == first_digest
  verify_mac_cloudkit_framework(project_path)
end

verify_no_temporary_mach_lookup_entitlements
puts 'Project generation is repeatable'
puts 'Mac target links CloudKit.framework'
puts 'Mac temporary Mach lookup entitlements are absent'
