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
    @steps = parse_steps  content  
    @doc = build @steps

  end

  def to_kbml(options={})


    @doc.xml options

  end

  private
  
  def build(steps)
    
    xml = RexleBuilder.new

    xml.kbml do
      
      steps.each do |h|

        comment = h[:user_comment]

        if comment then

          xml.comment! comment

          # is there text to be typed?
          typed = comment.scan(/\*[^*]+\*/)
          typed.each { |x| xml.type x[1..-2] }      

          xml.sleep if typed

        else  

          h[:keys].each do |keyx|

            key, modifier = keyx.split('-').reverse

            if modifier then
              xml.send(modifier.downcase.to_sym, {key: key.downcase})
            else
              xml.send(key.downcase.to_sym)
            end
          end

          xml.sleep

        end

      end

    end

    Rexle.new(xml.to_a)    
  end

  def parse_steps(s2)

    s = s2[/Recording Session.*(?=<)/]
    puts ('s: ' + s.inspect).debug if @debug    

    raw_steps = s.split(/(?=Step \d+:)/)
    summary = raw_steps.shift

    raw_steps.map do |entry|

      a = entry.split(/<br \/>/)
      raw_keys = a[0][/(?<=\[)[^\]]+/]
      keys = raw_keys ? raw_keys.gsub('...','').split : []

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
