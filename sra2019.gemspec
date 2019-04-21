Gem::Specification.new do |s|
  s.name = 'sra2019'
  s.version = '0.2.0'
  s.summary = 'Steps Recorder (MS Windows) Analyser 2019'
  s.authors = ['James Robertson']
  s.files = Dir['lib/sra2019.rb']
  s.add_runtime_dependency('rexle', '~> 1.5', '>=1.5.1')  
  s.signing_key = '../privatekeys/sra2019.pem'
  s.cert_chain  = ['gem-public_cert.pem']
  s.license = 'MIT'
  s.email = 'james@jamesrobertson.eu'
  s.homepage = 'https://github.com/jrobertson/sra2019'
end
