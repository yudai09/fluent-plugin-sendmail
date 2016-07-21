# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "fluent-plugin-sendmail"
  spec.version       = "0.1.1"
  spec.authors       = ["yudai09"]
  spec.email         = ["grandeur09@gmail.com"]
  spec.summary       = "Fluentd plugin to parse and merge sendmail syslog."
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/yudai09/fluent-plugin-sendmail"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]
  spec.add_runtime_dependency("lru_redux", [">= 0.8.4"])
  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency 'test-unit'
  spec.add_runtime_dependency "fluentd"
  spec.add_development_dependency "rake"
end
