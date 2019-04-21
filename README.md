# Introducing the sra2019 gem

    require 'sra2019'

    a = StepsRecorderAnalyser.new('/tmp/fun44/Recording_20190421_1546.mhtm').steps
    a[2]
    #=> {:step=>"3", :desc=>"User keyboard input on \"Open: (edit)\" in \"Run\" [..
    a[3]
    #=> {:step=>"4", :user_comment=>"\"Type notepad.exe\""} 


The sra2019 gem parses the Steps Recorder saved file and returns each step as a Hash object include step number, description, keys pressed, user comment and more.

## Resources

* sra2019 https://rubygems.org/gems/sra2019

sra2019 steps recorder windows log analyser gem
