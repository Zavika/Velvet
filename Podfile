platform :ios, '16.0'
project 'Velvet.xcodeproj'

target 'Velvet' do
  use_frameworks!
  pod 'MobileVLCKit', '~> 3.6'
end

post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |c|
      c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
      c.build_settings['ENABLE_BITCODE'] = 'NO'
    end
  end
end
