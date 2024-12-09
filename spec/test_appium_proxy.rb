require 'appium_lib'
require 'rspec'
require 'eyes_appium'
require 'spec_helper'

SAUCE_USERNAME = ENV['SAUCE_USERNAME']
SAUCE_ACCESS_KEY = ENV['SAUCE_ACCESS_KEY']
SAUCE_CONNECT_BIN = ENV['SAUCE_CONNECT_BIN']
SAUCE_TUNNEL_ID = ENV['SAUCE_TUNNEL_ID']
SAUCE_SERVER_URL = ENV['SAUCE_SERVER_URL']

APP_APK_URL = ENV['APP_APK_URL']

APPLITOOLS_PROXY_URL = ENV['APPLITOOLS_PROXY_URL']

RSpec.describe 'Appium Tests' do
  before(:all) do
    puts "Setting up Sauce Connect tunnel..."
    @tunnel = SauceTunnel.new(
      SAUCE_USERNAME,
      SAUCE_ACCESS_KEY,
      SAUCE_CONNECT_BIN,
      SAUCE_TUNNEL_ID,
      false,
      true,
      APPLITOOLS_PROXY_URL
    )
    @tunnel.start
  end

  after(:all) do
    puts "Tearing down Sauce Connect tunnel..."
    @tunnel.terminate
  end

  before(:each) do
    puts "Setting up test environment..."
    @eyes = Applitools::Selenium::Eyes.new
    @eyes.configure do |conf|
      conf.app_name = 'Applitools Eyes SDK'
      conf.test_name = 'Test Appium Sauce Connect Proxy'
    end
    @eyes.set_proxy(APPLITOOLS_PROXY_URL)

    caps = {
      deviceName: 'Samsung Galaxy S8 FHD GoogleAPI Emulator',
      platformName: 'Android',
      platformVersion: '7.0',
      app: APP_APK_URL
    }

    sauce_options = {
      name: 'test_appium_proxy',
      username: SAUCE_USERNAME,
      accessKey: SAUCE_ACCESS_KEY
    }

    sauce_options[:tunnelName] = SAUCE_TUNNEL_ID if SAUCE_TUNNEL_ID
    caps[:'sauce:options'] = sauce_options

    @driver = Appium::Driver.new(
      {
        caps: caps,
        appium_lib: {
          server_url: SAUCE_SERVER_URL
        }
      },
      true
    )
    @driver.start_driver
  end

  after(:each) do
    if @driver
      puts "Cleaning up test environment..."
      @driver.quit rescue nil
    end
  end

  it 'should test appium proxy', :sauce do
    puts "Running Appium proxy test..."
    @eyes.open(driver: @driver)
    @eyes.check(Applitools::Appium::Target.window)
    puts @eyes.close(true)
  end
end