#!/usr/bin/env ruby
# frozen_string_literal: true

# Registers Swift files under Macra/ that are on disk but not yet in the
# Xcode project. Files are anchored to the top-level `Macra` group with a
# path that carries the full nested folder, so the group UI stays flat but
# Xcode still resolves the actual on-disk location.
#
# EXCLUDES duplicate-symbol paths that currently conflict between the
# Features/MealPlanning and NutritionCore modules — the project is in the
# middle of a migration and registering every file causes ambiguous-type
# errors. Revisit once one side is fully retired.
#
# Usage: ruby Scripts/add_new_files_to_xcodeproj.rb [--dry-run]

require "pathname"
require "set"
require "optparse"
require "xcodeproj"

project_path = File.expand_path("../Macra.xcodeproj", __dir__)
target_name = "Macra"
source_root_name = "Macra"
source_root_abs = File.expand_path("../Macra", __dir__)

dry_run = false
OptionParser.new do |opts|
  opts.on("--dry-run") { dry_run = true }
end.parse!

# Feature/LabelSupplements is a fully self-contained legacy duplicate —
# NutritionCore now owns grading and scanning. Skip it entirely.
#
# Specific NutritionCore models duplicate types declared in
# Features/MealPlanning. The MealPlanning definitions are the ones the
# active feature code is built on, so exclude their NutritionCore doubles.
excluded_paths = %w[
  Features/LabelSupplements/
  NutritionCore/Models/MealPlan.swift
  NutritionCore/Models/MacroRecommendation.swift
].freeze

project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == target_name }
raise "Target #{target_name} not found" unless target

macra_group = project.main_group.children.find { |g| g.respond_to?(:path) && g.path == source_root_name }
raise "Couldn't find top-level '#{source_root_name}' group" unless macra_group

existing = Set.new(project.files.map { |f| f.real_path.to_s rescue nil }.compact)

missing = Dir.glob(File.join(source_root_abs, "**", "*.swift"))
  .reject { |p| existing.include?(p) }
  .sort

# Apply exclusion list.
missing = missing.reject do |p|
  rel = Pathname.new(p).relative_path_from(Pathname.new(source_root_abs)).to_s
  excluded_paths.any? { |ex| rel.start_with?(ex) }
end

if missing.empty?
  puts "No missing Swift files."
  exit 0
end

puts "Adding #{missing.length} file(s) to project:"
added = []

missing.each do |abs|
  rel = Pathname.new(abs).relative_path_from(Pathname.new(source_root_abs)).to_s

  file_ref = macra_group.new_reference(rel)
  sources_phase = target.source_build_phase
  unless sources_phase.files_references.include?(file_ref)
    sources_phase.add_file_reference(file_ref, true)
  end
  added << rel
  puts "  + #{rel}"
end

if dry_run
  puts "Dry run — not writing project."
  exit 0
end

project.save
puts "Added #{added.length} file(s) to #{project_path}"
