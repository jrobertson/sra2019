#!/usr/bin/env ruby

# file: sra2019.rb

# description: Steps Recorder (MS Windows) Analyser 2019


require 'rexle'
require 'rxfhelper'
require 'rexle-builder'



class StepsRecorderAnalyser
  using ColouredText

  attr_reader :steps

  def initialize(s, debug: false)

    @debug = debug
    content = RXFHelper.read(s).first
    puts ('content: ' + content.inspect).debug if @debug
    parse_steps  content  

  end

  def to_kbml()



  end

  private

  def parse_steps(s2)

    puts ('s2: ' + s2.inspect).debug if @debug
    s = s2[/Recording Session.*(?=<)/]

    raw_steps = s.split(/(?=Step \d+:)/)
    summary = raw_steps.shift

    @steps = raw_steps.map do |entry|

      a = entry.split(/<br \/>/)
      raw_keys = a[0][/(?<=\[)[^\]]+/]
      keys = raw_keys ? raw_keys.split : []

      raw_comment = a[0][/User Comment: (.*)/,1]

      if raw_comment then

        {
          step: a[0][/(?<=Step )\d+/],
          user_comment: raw_comment.gsub("&quot;",'"')
        }

      else
      
        {
          step: a[0][/(?<=Step )\d+/],
          desc: a[0][/(?:Step \d+: )(.*)/,1].gsub("&quot;",'"'),
          keys: keys ,
          program: a[1][/(?<=Program: ).*/],
          ui_elements: a[2][/(?<=UI Elements: ).*/].split(/,\s+/)
        }
      end

    end

  end

end
