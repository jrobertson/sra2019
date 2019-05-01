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
require 'ogginfo'
require 'wavefile'
require 'rxfhelper'
require 'wicked_pdf'
require 'mini_magick'
require 'archive/zip'
require 'pollyspeech'
require 'rexle-builder'


module WavTool
  include WaveFile
    
  def wav_silence(filename, duration: 1)

    square_cycle = [0] * 100 * duration
    buffer = Buffer.new(square_cycle, Format.new(:mono, :float, 44100))

    Writer.new(filename, Format.new(:mono, :pcm_16, 22050)) do |writer|
      220.times { writer.write(buffer) }
    end

  end
  
  def wav_concat(files, save_file='audio.wav')
    
    Writer.new(save_file, Format.new(:stereo, :pcm_16, 22050)) do |writer|

      files.each do |file_name|

        Reader.new(file_name).each_buffer(samples_per_buffer=4096) do |buffer|
          writer.write(buffer)
        end

      end
    end
    
  end
  
  def ogg_to_wav(oggfile, wavfile=oggfile.sub(/\.ogg$/,'.wav'))
    
    if block_given? then
      yield(oggfile)
    else
    `oggdec #{oggfile}`
    end
    
  end

end

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
  include WavTool

  attr_reader :start_time, :duration
  attr_accessor :steps
  

  def initialize(s, debug: false, savepath: '/tmp', title: 'Untitled', 
                 working_dir: '/tmp', pollyspeech: {access_key: nil, 
                 secret_key: nil, voice_id: 'Amy', 
                 cache_filepath: '/tmp/pollyspeech/cache'})

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

    @pollyspeech = PollySpeech.new(pollyspeech) if pollyspeech[:access_key]
    
  end
  
  # adds the audio track to the video file
  # mp4 in avi out
  #
  def add_audio_track(audio_file, video_file, target_video)
    
    if block_given? then
      yield(audio_file, video_file, target_video)
    else
      `ffmpeg -i #{video_file} -i #{audio_file} -codec copy -shortest #{target_video} -y`
    end
    
  end
  
  # mp4 in mp4 out
  #
  def add_subtitles(source, destination)
    
    
    subtitles = File.join(@working_dir, 's.srt')
    File.write subtitles, to_srt()
    
    if block_given? then
      yield(source, subtitles, destination)
    else
      `ffmpeg -i #{source} -i #{subtitles} -c copy -c:s mov_text #{destination} -y`
    end
    
  end
  
  def build_video(source, destination)
    
    dir = File.dirname(source)
    file = File.basename(source)
    
    tidy!
    
    vid2 = File.join(dir, file.sub(/\.mp4$/,'b\0'))
    trim_video source, vid2
    
    vid3 = File.join(dir, file.sub(/\.mp4$/,'c.avi'))

    generate_audio
    add_audio_track File.join(@working_dir, 'audio.wav'), vid2, vid3

    
    vid4 = File.join(dir, file.sub(/\.avi$/,'d\0'))
    resize_video vid3, vid4
    
    vid5 = File.join(dir, file.sub(/\.mp4$/,'e\0'))
    transcode_video(vid4, vid5)
    add_subtitles(vid5, destination)    
    
  end  
    
  
  def generate_audio(wav: true)
    
    return nil unless @pollyspeech
    
    @steps.each.with_index do |x, i|
      
      puts 'x.desc: ' + x.desc.inspect if @debug
      filename = "voice#{i+1}.ogg"
      
      x.audio = filename
      file = File.join(@working_dir, filename)
      @pollyspeech.tts(x.desc.force_encoding('UTF-8'), file)
      
      x.audio_duration = OggInfo.open(file) {|ogg| ogg.length.to_i }
      
      if @debug then
        puts ('x.duration: ' + x.duration.inspect).debug
        puts ('x.audio_duration: ' + x.audio_duration.inspect).debug
      end
      
      duration = x.duration - x.audio_duration
      x.silence_duration = duration >= 0 ? duration : 0
      
      if wav then
        
        silent_file = File.join(@working_dir, "silence#{(i+1).to_s}.wav")
        puts 'x.silence_duration: ' + x.silence_duration.inspect if @debug
        wav_silence silent_file, duration: x.silence_duration        
        ogg_to_wav File.join(@working_dir, "voice#{i+1}.ogg")            
        
      end
      
      sleep 0.02
      
    end
    
    if wav then
      
      intro = File.join(@working_dir, 'intro.wav')
      wav_silence intro
      
      files = @steps.length.times.flat_map do |n|
        [
          File.join(@working_dir, "voice#{n+1}.wav"), 
          File.join(@working_dir, "silence#{n+1}.wav")
        ]
      end
      
      files.prepend intro
      
      wav_concat files, File.join(@working_dir, 'audio.wav')
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
  
  # avi in avi out
  def resize_video(source, destination)
    `ffmpeg -i #{source} -vf scale="720:-1" #{destination} -y`
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
  
  def transcode_video(avi, mp4)
    
    if block_given? then
      yield(avi, mp4)
    else
      `ffmpeg -i #{avi} #{mp4} -y`
    end
    
  end
  
  def trim_video(video, newvideo)
    
    start = @steps.first.time - 4
    t1, t2 = [start, @steps.last.time - 2 ].map do |step|
      "%02d:%02d:%02d" % (step.to_hms.reverse + [0,0]).take(3).reverse
    end
    
    `ffmpeg -i #{video} -ss #{t1} -t #{t2} -async 1 #{newvideo} -y`
    
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
  
  def to_srt(offset=-(@steps.first.time - 2))

    lines = to_subtitles(offset).strip.lines.map.with_index do |x, i|

      raw_times, subtitle = x.split(/ /,2)
      puts ('raw_times: ' + raw_times.inspect).debug if @debug
      start_time, end_time = raw_times.split('-',2)
      times = [("%02d:%02d:%02d,000" % ([0, 0 ] + start_time.split(/\D/)\
                                    .map(&:to_i)).reverse.take(3).reverse), \
               '-->', \
              ("%02d:%02d:%02d,000" % ([0, 0 ] + end_time.split(/\D/).map(&:to_i))\
               .reverse.take(3).reverse)].join(' ')

      [i+1, times, subtitle].join("\n")

    end

    lines.join("\n")    
    
  end
  
  def to_subtitles(offset=-(@steps.first.time - 2))
    
    raw_times = @steps.map {|x| [x.time, x.time + x.audio_duration + 1]} 
    

    times = raw_times.map do |x|

      x.map do |sec|
        a = Subunit.new(units={minutes:60}, seconds: sec+offset).to_h.to_a
        a.map {|x|"%d%s" % [x[1], x[0][0]] }.join('')
      end.join('-')
      
    end
    
    times.zip(@steps.map(&:desc)).map {|x| x.join(' ')}.join("\n")
                          
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
