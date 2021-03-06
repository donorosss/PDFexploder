#!/usr/bin/ruby

require 'fileutils'
require 'csv'

require 'section'

class Book
  attr_reader :name, :filename, :index_filename, :last_page
  attr_accessor :sections, :description

  @@all = []

  def initialize(filename, index_filename, description)
    @filename = filename
    @index_filename = index_filename
    @name = File.basename(filename).sub(/\.pdf$/, '')
    @description = description
    @@all.push self
    @sections = []

    # Hash mapping page number to Array of sections appearing on that page
    # (multiple sections could appear on one page)
    @section_pages = {}

    read_index
    get_last_page
    calculate_last_pages
    get_pages_from_sections
    validate_page_numbers
  end

  def self.all
    @@all
  end

  def add_section(section)
    sections << section
  end

  def get_pages_from_sections
    sections.each do |section|
      section.pages.each do |page|
        (@section_pages[page] ||= []) << section
      end
    end
  end

  def validate_page_numbers
    too_high_sections = @section_pages.inject({}) do |acc, kv|
      page, sections = *kv
      if sections && page > last_page
        sections.each do |section|
          acc[section] ||= []
          acc[section] << page
        end
      end
      acc
    end
    if too_high_sections.any?
      warn "Sections with pages too high:"
      too_high_sections.each do |section, pages|
        warn "  #{section.name}: " + pages.join(", ")
      end
      exit 1
    end
  end

  def inspect
    "#<Book:#{name} (#{sections.length} sections)>"
  end

  def <=>(other)
    @description <=> other.description
  end

  def read_index
    $stderr.puts "Processing #{index_filename} ..."
    File.open(index_filename) do |file|
      file.each_line do |line|
        # $stderr.puts "  #{name}: #{line}"
        next if line =~ /^\s*(#|$)/
        line.chomp!

        begin
          name, first, last = CSV.parse_line(line)
        rescue CSV::MalformedCSVError => e
          abort "Failed to parse line #{file.lineno} of #{index_filename} (#{e}):\n[#{line}]"
        end
        unless first =~ /^\d+$/
          warn "Invalid first page '#{first}' for '#{name}'; skipping"
          next
        end
        Section.new(name, self, first.to_i, last ? last.to_i : nil)
      end
    end

    sections.sort!
  end

  def get_last_page
    success, info, err = Command.run(['pdfinfo', filename])
    raise "pdfinfo #{filename} failed" unless success
    unless info =~ /^Pages:\s+(\d+)$/
      raise "pdfinfo #{filename} didn't return last page"
    end
    @last_page = $1.to_i
  end

  def calculate_last_pages
    # Look at the page numbers of adjacent sections to calculate
    # how many pages each section occupies
    for i in 0..(sections.length - 2)
      this_section = sections[i]
      next if this_section.last_page

      # Last page was not specified so figure it out by looking at the
      # page the next section starts on
      next_section = sections[i+1]
      pages_until_next_section = next_section.first_page - this_section.first_page
      num_pages =
        if pages_until_next_section == 0
          1
        elsif pages_until_next_section > 6
          raise "WARNING: #{this_section.name} p#{this_section.first_page} in #{name} " \
          "followed by #{next_section.name} p#{next_section.first_page}"
        else
          pages_until_next_section
        end
      this_section.last_page = this_section.first_page + num_pages - 1
    end
  end

  def missing_pages
    (1..last_page).reject { |i| @section_pages[i] }
  end

  def explode(split_dir)
    #FileUtils.rm_rf(split_dir)
    Dir.mkdir(split_dir) unless File.directory? split_dir
    $stderr.puts "Exploding #{name} to #{split_dir} ..."
    sections.each { |section| section.extract(split_dir) }
  end
end
