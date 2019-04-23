#!/usr/bin/env ruby

# file: sra2019.rb

# description: Steps Recorder (MS Windows) Analyser 2019


require 'hlt'
require 'rexle'
require 'base64'
require 'zip/zip'
require 'rxfhelper'
require 'wicked_pdf'
require 'mini_magick'
require 'archive/zip'
require 'rexle-builder'



class StepsRecorderAnalyser
  using ColouredText

  attr_reader :steps
  

  def initialize(s, debug: false, savepath: '/tmp', title: 'Untitled')

    @savepath, @title, @debug = savepath, title, debug
    
    raw_content, type = RXFHelper.read(s)
    
    content = if type == :file and File.extname(s) == '.zip' then
      Zip::ZipFile.new(s).instance_eval {read(to_a[0].name)}
    else
      raw_content
    end

    puts ('content: ' + content.inspect).debug if @debug
    
    all_steps = parse_steps  content  
    @doc = build all_steps
    @steps = all_steps.select {|x| x[:user_comment]}

  end

  def to_kbml(options={})


    @doc.xml options

  end
  
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
  
  def to_pdf(pdf_file=File.join(@savepath, 'sra' + Time.now.to_i.to_s, 
                              @title.gsub(/ /,'-') + '.pdf'))
    
    dir = File.dirname(pdf_file)
    html_file = File.join(dir, 'index.html')
    
    to_html(dir)
    pdf = WickedPdf.new.pdf_from_html_file(html_file)
    File.write pdf_file, pdf
    
  end
  

  def to_zip()
    
    project = 'sra' + Time.now.to_i.to_s
    newdir = File.join(@savepath, project)
    zipfile = newdir + '.zip'
    
    to_pdf(File.join(newdir, @title.gsub(/ /,'-') + '.pdf'))    

    Archive::Zip.archive(zipfile, newdir)
    
    'saved to ' +  zipfile
    
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
    
    report = Rexle.new s[/<Report>.*<\/Report>/m]        
    
    e = report.root.element('UserActionData/RecordSession/EachAction' + 
                            "[@ActionNumber='#{n}']/HighlightXYWH")
            
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
        
        {
          step: n,
          user_comment: raw_comment.gsub("&quot;",''),
          screenshot: extract_image(s, n)
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
