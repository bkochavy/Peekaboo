#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'

ROOT = File.expand_path('..', __dir__)
GENERATOR = File.join(__dir__, 'generate_project.rb')
MAC_ENTITLEMENT_PATHS = %w[
  Peekaboo/Peekaboo.entitlements
  Peekaboo/PeekabooDebug.entitlements
  Peekaboo/PeekabooLocal.entitlements
].freeze
MACH_LOOKUP_KEY = 'com.apple.security.temporary-exception.mach-lookup.global-name'
REQUIRED_MACH_SERVICES = %w[
  com.apple.cloudd
  com.apple.duetactivityscheduler
].freeze

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

def verify_mac_sync_entitlements
  MAC_ENTITLEMENT_PATHS.each do |path|
    services = read_plist(path).fetch(MACH_LOOKUP_KEY, [])
    missing_services = REQUIRED_MACH_SERVICES - services
    abort "#{path} is missing #{missing_services.join(', ')}" unless missing_services.empty?
  end
end

Dir.mktmpdir('peekaboo-project-check') do |directory|
  project_path = File.join(directory, 'generated', 'Peekaboo.xcodeproj')
  generate(project_path)
  first_digest = digest(project_path)
  generate(project_path)
  abort 'Project generation is not repeatable' unless digest(project_path) == first_digest
end

verify_mac_sync_entitlements
puts 'Project generation is repeatable'
puts 'Mac sync entitlements are present'
