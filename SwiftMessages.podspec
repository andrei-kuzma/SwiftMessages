Pod::Spec.new do |spec|
  spec.name             = 'SwiftMessages'
  spec.version          = '3.3.4-lgi-swift5'
  spec.license          = { :type => 'MIT' }
  spec.homepage         = 'https://github.com/andrei-kuzma/SwiftMessages'
  spec.authors          = { 'Timothy Moose' => 'tim@swiftkick.it' }
  spec.summary          = 'A very flexible message bar for iOS written in Swift.'
  spec.source           = { :git => 'https://github.com/andrei-kuzma/SwiftMessages.git', :branch => 'swift5'}
  spec.platform         = :ios, '9.0'
  spec.ios.deployment_target = '9.0'
  spec.swift_version = '5.0'
  spec.source_files     = 'SwiftMessages/**/*.swift'
  spec.resource_bundles = {'SwiftMessages' => ['SwiftMessages/Resources/**/*']}
  spec.framework        = 'UIKit'
  spec.requires_arc     = true
end
