Gem::Specification.new do |s|
  s.name = 'sra2019'
  s.version = '0.7.2'
  s.summary = 'Steps Recorder (MS Windows) Analyser 2019'
  s.authors = ['James Robertson']
  s.files = Dir['lib/sra2019.rb']  
  s.add_runtime_dependency('hlt', '~> 0.6', '>=0.6.3')
  s.add_runtime_dependency('subunit', '~> 0.3', '>=0.3.0')
  s.add_runtime_dependency('ruby-ogginfo', '~> 0.7', '>=0.7.2')
  s.add_runtime_dependency('wavefile', '~> 1.1', '>=1.1.0')
  s.add_runtime_dependency('archive-zip', '~> 0.12', '>=0.12.0')
  s.add_runtime_dependency('wicked_pdf', '~> 1.2', '>=1.2.2')
  s.add_runtime_dependency('pollyspeech', '~> 0.2', '>=0.2.0')
  s.add_runtime_dependency('mini_magick', '~> 4.9', '>=4.9.3')    
  s.signing_key = '../privatekeys/sra2019.pem'
  s.cert_chain  = ['gem-public_cert.pem']
  s.license = 'MIT'
  s.email = 'james@jamesrobertson.eu'
  s.homepage = 'https://github.com/jrobertson/sra2019'
end
