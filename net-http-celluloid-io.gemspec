# encoding: utf-8
require File.expand_path('../lib/net/http/celluloid_io/version', __FILE__)

Gem::Specification.new do |gem|
  gem.name          = "net-http-celluloid-io"
  gem.version       = Net::HTTP::CelluloidIO::VERSION
  gem.license       = 'MIT'
  gem.authors       = ["Masahiro Fujiwara"]
  gem.email         = ["fujiwara.masahiro@gmail.com"]
  gem.summary       = "Celluloid::IO backend for net/http"
  gem.description   = "Celluloid::IO backend for net/http"
  gem.homepage      = "http://github.com/unakatsuo/net-http-celluloid-io"

  gem.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.require_paths = ["lib"]

  gem.add_dependency 'celluloid-io', '>= 0.15.0'

  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'rspec'
end
