#!/usr/bin/ruby

require 'command'

class Section
  attr_reader :name, :book, :first_page, :latex_name
  attr_accessor :last_page, :sections

  @@all = []

  def initialize(name, book, first_page, last_page=nil)
    @name = name
    @latex_name = name.gsub(/[#&%]/, "\\\\&") # escape LaTeX meta-characters
    @book = book
    book.add_section self
    @first_page = first_page
    @last_page = last_page
    @@all.push self
  end

  def inspect
    "#<%s: %s (%s)>" % [self.class, name, pages.to_a.join(",")]
  end

  def to_s
    inspect
  end

  def self.all
    @@all
  end

  def <=>(other)
    @first_page <=> other.first_page
  end

  def pages
    last_page.nil? ? [first_page] : first_page..last_page
  end

  def pages_string
    (last_page.nil? || last_page == first_page) ?
      first_page.to_s : "%s-%s" % [first_page, last_page]
  end

  def pages_p_string
    (first_page == last_page ? "p" : "pp") + pages_string
  end

  def filename
    "#{name} (#{book.name} #{pages_p_string}).pdf".gsub('/', '_')
  end

  def extract(dir)
    outfile = dir + '/' + filename
    if File.exists? outfile
      $stderr.puts "  exists:    #{filename}"
      return
    end

    cmd = [ 'pdfjam', book.filename, "#{first_page}-#{last_page}", '-o', outfile ]
    success, out, err = Command.run(cmd)
    unless success
      abort(("-" * 70) + "\n" +
            "pdfjam failed with args #{cmd[1..-1]}\n" +
            "STDOUT:\n#{out}\n" +
            "STDERR:\n#{err}\n")
    end
    $stderr.puts "  extracted: #{filename}"
  end
end
