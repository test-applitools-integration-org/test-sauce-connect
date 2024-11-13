require 'appium_lib'
require 'rspec'
require 'eyes_appium'
require 'rest-client'
require 'json'
require 'timeout'
require 'retriable'


SAUCE_USERNAME = ENV['SAUCE_USERNAME']
SAUCE_ACCESS_KEY = ENV['SAUCE_ACCESS_KEY']
SAUCE_CONNECT_BIN = ENV['SAUCE_CONNECT_BIN']
SAUCE_TUNNEL_ID = ENV['SAUCE_TUNNEL_ID']
SAUCE_SERVER_URL = ENV['SAUCE_SERVER_URL']

APP_APK_URL = ENV['APP_APK_URL']

APPLITOOLS_PROXY_URL = ENV['APPLITOOLS_PROXY_URL']

class SauceTunnel
  attr_reader :sauce_connect

  MAX_RETRIES = 5
  RETRY_INTERVAL = 8
  CONNECTION_TIMEOUT = 10

  def initialize(username, access_key, sc_path, tunnel_name, dns, no_ssl_bump_domains)
    @sauce_connect = nil
    @sc_path = sc_path
    @tunnel_name = tunnel_name
    @dns = dns
    @no_ssl_bump_domains = no_ssl_bump_domains
    @user = username
    @access_key = access_key
  end

  def process_alive?(pid)
    begin
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end
  end

  def check_connection(readiness_url)
    response = Retriable.retriable(
      tries: 3,
      base_interval: 1,
      max_interval: 5,
      on: [RestClient::Exception, Timeout::Error, Errno::ECONNRESET]
    ) do
      RestClient::Request.execute(
        method: :get,
        url: readiness_url,
        timeout: CONNECTION_TIMEOUT,
        open_timeout: CONNECTION_TIMEOUT
      )
    end

    JSON.parse(response.body)['status'] == 'connected' if response.code == 200
  rescue StandardError => e
    puts "Connection check failed: #{e.message}"
    false
  end

  def wait_for_sc_readiness(timeout_seconds = 300)
    readiness_url = 'http://127.0.0.1:8080/status'
    start_time = Time.now
    attempt = 1

    loop do
      time_elapsed = Time.now - start_time
      raise TimeoutError, "Service readiness check timed out after #{timeout_seconds} seconds" if time_elapsed > timeout_seconds

      puts "Attempt #{attempt} to check Sauce Connect status..."

      if check_connection(readiness_url)
        puts 'Sauce Connect established connection successfully'
        return true
      end

      attempt += 1
      remaining_time = timeout_seconds - time_elapsed
      sleep_time = [RETRY_INTERVAL, remaining_time].min

      puts "Retrying in #{sleep_time} seconds... (#{remaining_time.to_i}s remaining)"
      sleep sleep_time
    end
  end

  def start
    Retriable.retriable(
      tries: MAX_RETRIES,
      base_interval: 2,
      max_interval: 10,
      on: [StandardError]
    ) do
      sc_call = "#{@sc_path} legacy -u #{@user} -k #{@access_key} --region us-west " \
                "--tunnel-name #{@tunnel_name} --status-address 127.0.0.1:8080 --logfile logs/sc.log " \
                "--verbose"

      sc_call += " --dns #{@dns}" if @dns
      sc_call += " --no-ssl-bump-domains #{@no_ssl_bump_domains}" if @no_ssl_bump_domains

      sc_call = sc_call.split(' ') unless Gem.win_platform?

      puts sc_call.join(' ') if sc_call.is_a?(Array)
      puts sc_call if sc_call.is_a?(String)

      @sauce_connect = IO.popen(sc_call, err: [:child, :out])

      wait_for_sc_readiness
    end
  end

  def terminate
    if @sauce_connect
      puts 'Terminating Sauce Connect tunnel'
      Process.kill('TERM', @sauce_connect.pid)

      Timeout.timeout(10) do
        while process_alive?(@sauce_connect.pid)
          sleep 1
        end
      end
    end
  rescue Timeout::Error
    puts 'Force killing Sauce Connect tunnel'
    Process.kill('KILL', @sauce_connect.pid) rescue nil
  rescue Errno::ESRCH => e
    puts "Process already terminated: #{e.message}"
  rescue StandardError => e
    puts "Error during termination: #{e.message}"
  ensure
    @sauce_connect.close if @sauce_connect
  end
end


RSpec.describe 'Appium Tests' do
  before(:all) do
    puts "Setting up Sauce Connect tunnel..."
    @tunnel = SauceTunnel.new(
      SAUCE_USERNAME,
      SAUCE_ACCESS_KEY,
      SAUCE_CONNECT_BIN,
      SAUCE_TUNNEL_ID,
      false,
      true
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

    sauce_options[:tunnelName] = ENV['SAUCE_TUNNEL_ID'] if ENV['SAUCE_TUNNEL_ID']
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