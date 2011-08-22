# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "kyotoindex/version"

Gem::Specification.new do |s|
  s.name        = "kyotoindex"
  s.version     = KyotoIndex::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Ricky Robinson"]
  s.email       = ["ricky@rickyrobinson.id.au"]
  s.homepage    = ""
  s.summary     = %q{Full text search using Kyoto Tycoon}
  s.description = %q{Full text search using Kyoto Tycoon}

  s.rubyforge_project = "kyotoindex"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
  
  s.add_dependency "msgpack"
  s.add_dependency "kyototycoon"
  s.add_dependency "activesupport"
  
end
