#!/usr/bin/env ruby

# file: sra2019.rb

# description: Steps Recorder (MS Windows) Analyser 2019


require 'hlt'
require 'rexle'
require 'base64'
require 'ostruct'
require 'subunit'
require 'zip/zip'
require 'dynarex'
require 'rxfhelper'
require 'wicked_pdf'
require 'mini_magick'
require 'archive/zip'
require 'rexle-builder'


module TimeHelper

  refine String do
    def to_time()
      Time.strptime(self, "%H:%M:%S")
    end
  end
  
  refine Integer do
    def to_hms
      Subunit.new(units={minutes:60}, seconds: self).to_a
    end
  end

end



class StepsRecorderAnalyser
  using ColouredText
  using TimeHelper
  
  attr_reader :start_time, :duration
  attr_accessor :steps
  

  def initialize(s, debug: false, savepath: '/tmp', title: 'Untitled', 
                 working_dir: '/tmp')

    @savepath, @title, @working_dir, @debug = savepath, title, 
        working_dir, debug
    
    raw_content, type = RXFHelper.read(s)
    
    content = if type == :file and File.extname(s) == '.zip' then
      Zip::ZipFile.new(s).instance_eval {read(to_a[0].name)}
    else
      raw_content
    end

    puts ('content: ' + content.inspect).debug if @debug
    
    @actions = parse_report content
    @all_steps = parse_steps  content  
    @doc = build @all_steps
    steps = @all_steps.select {|x| x[:user_comment]}
    @steps = steps.any? ? steps : @all_steps
    
    # find the duration for each step
    @steps.each.with_index do |x, i|
      
      x.duration = if i < @steps.length - 1 then
        @steps[i+1].time - x.time 
      else
        @duration - x.time 
      end
      
    end
    
  end
  

  def import(s)
    
    @dx = Dynarex.new
    @dx.import s
    
  end
  
  def remove_steps(a)
    a.each {|n| @steps[n] = nil }
    @steps.compact!    
  end

  
  def tidy!()

    verbose_level = 0

    @steps.each do |x|

      x.desc.gsub!(/\s*\([^\)]+\)\s*/,'')
      x.desc.sub!(/ in "\w+"$/,'')
      x.desc.sub!(/"User account for [^"]+"/,'the User account icon.')
      
      if x.desc =~ /User left click/ and verbose_level == 0 then

        x.desc.sub!(/User left click/, 'Using the mouse, left click')
        verbose_level = 1

      elsif x.desc =~ /User left click/ and verbose_level == 1

        x.desc.sub!(/User left click/, 'Left click')
        verbose_level = 2

      elsif x.desc =~ /User left click/ and verbose_level == 2

        x.desc.sub!(/User left click/, 'Click')
        verbose_level = 3

      elsif x.desc =~ /User left click/ and verbose_level == 3

        x.desc.sub!(/User left click on/, 'Select')

      else
        verbose_level = 0
      end

    end
    
  end
  

  # Returns a Dynarex object
  #
  def to_dx()
    
    @dx = Dynarex.new 'instructions/instruction(step, imgsrc, description)'
    @dx.summary[:rawdoc_type] = 'rowx'
    
    @steps.each.with_index do |h, i|
      
      @dx.create step: i+1, imgsrc: "screenshot#{i+1}.jpg", 
          description: h[:user_comment] || h[:desc]
      
    end
    
    @dx
    
  end

  def to_kbml(options={})

    @doc.xml options

  end
  

  # Writes the steps to an HTML file
  #
  def to_html(filepath=File.join(@savepath, 'sra' + Time.now.to_i.to_s))
    
    # save the image files to a file directory.
    # name the sub-directory using the date and time?

    imgpath = File.join(filepath, 'images')
    csspath = File.join(filepath, 'css')
    
    [filepath, imgpath, csspath].each {|x|  FileUtils.mkdir x}

    @steps.each.with_index do |x, i|
      
      File.open(File.join(imgpath, "screenshot#{i}.jpg" ), 'wb') \
        {|f| f.write(x[:screenshot]) }

    end
    

    rows = @steps.map.with_index do |x, i|

li = "
      li
        markdown:
          #{x[:user_comment]}
          
          ![](images/screenshot#{i}.jpg)
"         
    
    end

@sliml=<<EOF
html
  head
    title #{@title}: #{@steps.length} Steps (with Pictures)    
    link rel='stylesheet' type='text/css' href='css/layout.css' media='screen,  projection, tv'
    link rel='stylesheet' type='text/css' href='css/style.css' media='screen,  projection, tv'
    link rel='stylesheet' type='text/css' href='css/print.css' media='print'
  body
    h1 #{@title}

    ol
      #{rows.join("\n").lstrip}
EOF

    html = Rexle.new(Hlt.new(@sliml).to_html)\
        .root.element('html').xml pretty: true
    File.write File.join(filepath, 'index.html'), html

    %w(layout style print).each \
        {|x| File.write File.join(csspath, "%s.css" % x), ''}
    
    'saved'
    
  end
  
  def to_sliml()
    @sliml
  end
  

  
  def to_subtitles(offset=-(@steps.first.time - 1))
              
    @steps.map do |x|
      
      secs = x.time.to_i+offset
      
      if secs < 1 then
        raise "to_subtitles: time can't be negative. Reduce the offset value"   
      end
      
      a = Subunit.new(units={minutes:60}, seconds: secs).to_h.to_a
      time = a.map {|x|"%d%s" % [x[1], x[0][0]] }.join('')
      "%s %s " % [time, x.desc]
      
    end
  end
  
  # Writes the steps to a PDF file
  #
  def to_pdf(pdf_file=File.join(@savepath, 'sra' + Time.now.to_i.to_s, 
                              @title.gsub(/ /,'-') + '.pdf'))
    
    dir = File.dirname(pdf_file)
    html_file = File.join(dir, 'index.html')
    
    to_html(dir)
    pdf = WickedPdf.new.pdf_from_html_file(html_file)
    File.write pdf_file, pdf
    
  end
  
  # Compresses the HTML file directory to a ZIP file
  #
  def to_zip()
    
    project = 'sra' + Time.now.to_i.to_s
    newdir = File.join(@savepath, project)
    zipfile = newdir + '.zip'
    
    to_html(File.join(newdir))    
    #to_pdf(File.join(newdir, @title.gsub(/ /,'-') + '.pdf'))    

    Archive::Zip.archive(zipfile, newdir)
    
    zipfile
    
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
  
  
  def extract_image(s, n)
        
    action = @actions[n-1]          
    puts 'action: ' + action.inspect if @debug
    e = action.element('HighlightXYWH')
    return unless e
    y, x, w, h = e.text.split(',').map(&:to_i)

    jpg_file = action.element('ScreenshotFileName/text()')
    return unless jpg_file
    
    img_data = s[/(?<=Content-Location: #{jpg_file}\r\n\r\n)[^--]+/m]    
    puts ('img_data: ' + img_data.inspect).debug if @debug
    
    image = MiniMagick::Image.read Base64.decode64(img_data.rstrip)
    
    # crop along the red boundary and remove the red boundary
    image.crop "%sx%s+%s+%s" % [w - 5, h - 5, x + 3, y + 3]
    image.to_blob
    
  end
  
  def parse_report(s)
    
    report = Rexle.new s[/<Report>.*<\/Report>/m]            
    session = report.root.element('UserActionData/RecordSession')
    puts 'session: ' + session.inspect if @debug
    puts 'attributes: ' + session.attributes.inspect if @debug
    
    @start_time, stop_time = %w(Start Stop).map do |x|
      v = session.attributes[(x + 'Time').to_sym]
      puts 'v: ' + v.inspect if @debug
      v.to_time
    end
    
    @duration = stop_time - @start_time
    
    session.xpath('EachAction')    
    
  end

  def parse_steps(s)

    s2 = s[/Recording Session.*(?=<)/]
    puts ('s: ' + s.inspect).debug if @debug    

    raw_steps = s2.split(/(?=Step \d+:)/)
    summary = raw_steps.shift

    raw_steps.map do |entry|

      a = entry.split(/<br \/>/)
      raw_keys = a[0][/(?<=\[)[^\]]+/]
      keys = raw_keys ? raw_keys.gsub('...','').split : []

      raw_comment = a[0][/User Comment: (.*)/,1]
      
      n = a[0][/(?<=Step )\d+/].to_i
      puts ('n: ' + n.inspect).debug if @debug
      
      time = (@actions[n-1].attributes[:Time].to_time - @start_time).to_i

      
      h = if raw_comment then        
        
        {
          user_comment: raw_comment.gsub("&quot;",'')          
        }

      else
      
        {
          desc: a[0][/(?:Step \d+: )(.*)/,1].gsub('&amp;','&')\
            .gsub("&quot;",'"').sub(/\s+\[[^\[]+\]$/,''),
          keys: keys ,
          program: a[1][/(?<=Program: ).*/],
          ui_elements: a[2][/(?<=UI Elements: ).*/].split(/,\s+/)
        }
      end
      
      steps = {step: n, time: time, screenshot: extract_image(s, n)}.merge(h)
      OpenStruct.new(steps)

    end

  end

end
