#!/usr/bin/env ruby

# file: sra2019.rb

# description: Steps Recorder (MS Windows) Analyser 2019


require 'rexle'
require 'base64'
require 'rxfhelper'
require "mini_magick"
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
  
  def extract_image(s, e)
        
    y, x, w, h = e.text.split(',').map(&:to_i)

    jpg_file = e.parent.element('ScreenshotFileName/text()')
    img_data = s[/(?<=Content-Location: #{jpg_file}\r\n\r\n)[^--]+/m]    
    puts ('img_data: ' + img_data.inspect).debug if @debug
    
    image = MiniMagick::Image.read Base64.decode64(img_data.rstrip)
    
    # crop along the red boundary and remove the red boundary
    image.crop "%sx%s+%s+%s" % [w - 5, h - 5, x + 3, y + 3]
    image.to_blob
    
  end

  def parse_steps(s)

    s2 = s[/Recording Session.*(?=<)/]
    puts ('s: ' + s.inspect).debug if @debug    

    report = Rexle.new s[/<Report>.*<\/Report>/m]    
    raw_steps = s2.split(/(?=Step \d+:)/)
    summary = raw_steps.shift

    raw_steps.map do |entry|

      a = entry.split(/<br \/>/)
      raw_keys = a[0][/(?<=\[)[^\]]+/]
      keys = raw_keys ? raw_keys.gsub('...','').split : []

      raw_comment = a[0][/User Comment: (.*)/,1]
      
      n = a[0][/(?<=Step )\d+/]      
      puts ('n: ' + n.inspect).debug if @debug

      if raw_comment then
        

        e = report.root.element('UserActionData/RecordSession/EachAction' + 
                                "[@ActionNumber='#{n}']/HighlightXYWH")
        
        {
          step: n,
          user_comment: raw_comment.gsub("&quot;",'"'),
          screenshot: extract_image(s, e)
        }

      else
      
        {
          step: n,
          desc: a[0][/(?:Step \d+: )(.*)/,1].gsub("&quot;",'"'),
          keys: keys ,
          program: a[1][/(?<=Program: ).*/],
          ui_elements: a[2][/(?<=UI Elements: ).*/].split(/,\s+/)
        }
      end

    end

  end

end
