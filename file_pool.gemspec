# -*- encoding: utf-8 -*-
$:.unshift File.expand_path("../lib", __FILE__)
require "file_pool/version"

Gem::Specification.new do |gem|
  gem.authors       = ["robokopp (Robert Anniés)"]
  gem.email         = ["robokopp@fernwerk.net"]
  gem.description   = %q{FilePool helps to manage a large number of files in a Ruby
project. It takes care of the storage of files in a balanced directory
tree and generates unique identifiers for all files.
}
  gem.summary       = %q{Manage a large number files in a pool}
  gem.homepage      = "https://github.com/robokopp/file_pool"

  gem.files         = ["lib/file_pool.rb", "lib/file_pool/version.rb"]
  gem.test_files    = ["test/test_file_pool.rb"]
  gem.extra_rdoc_files = ["README.md"]
  gem.name          = "file_pool"
  gem.require_paths = ["lib"]
  gem.version       = FilePool::VERSION
  gem.add_development_dependency('shoulda')
  gem.add_dependency('uuidtools', '~> 2.1.2')

end
