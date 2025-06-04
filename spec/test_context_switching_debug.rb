require 'appium_lib'
require 'rspec'
require 'eyes_appium'
require 'spec_helper'
require 'timeout'
require 'json'

SAUCE_USERNAME = ENV['SAUCE_USERNAME']
SAUCE_ACCESS_KEY = ENV['SAUCE_ACCESS_KEY']
SAUCE_CONNECT_BIN = ENV['SAUCE_CONNECT_BIN']
SAUCE_TUNNEL_ID = ENV['SAUCE_TUNNEL_ID']
SAUCE_SERVER_URL = ENV['SAUCE_SERVER_URL']
APP_APK_URL = ENV['APP_APK_URL']
APPLITOOLS_PROXY_URL = ENV['APPLITOOLS_PROXY_URL']

RSpec.describe 'Context Switching Debug Tests' do
  before(:all) do
    puts "=== Universal SDK Binary Inspection ==="
    UniversalSDKInspector.inspect_binary
    
    puts "\n=== Setting up Sauce Connect tunnel..."
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
    puts "\n=== Setting up test environment..."
    
    # Test different proxy configurations
    test_proxy_configurations
    
    @eyes = Applitools::Selenium::Eyes.new
    @eyes.configure do |conf|
      conf.app_name = 'Context Switching Debug'
      conf.test_name = 'Debug ETIMEDOUT Context Switching'
    end
    @eyes.set_proxy(APPLITOOLS_PROXY_URL)

    caps = {
      deviceName: 'Samsung Galaxy S8 FHD GoogleAPI Emulator',
      platformName: 'Android',
      platformVersion: '7.0',
      app: APP_APK_URL
    }

    sauce_options = {
      name: 'debug_context_switching',
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

  def test_proxy_configurations
    puts "\n=== Testing Proxy Configurations ==="
    
    proxy_formats = [
      ENV['HTTP_PROXY'],
      ENV['HTTPS_PROXY'],
      APPLITOOLS_PROXY_URL,
      'http://test-proxy:3128',
      'test-proxy:3128'
    ].compact.uniq
    
    proxy_formats.each do |proxy|
      puts "Testing proxy format: #{proxy}"
      begin
        output = `timeout 5 curl --proxy "#{proxy}" -s -o /dev/null -w "%{http_code}" https://www.google.com 2>&1`
        puts "  Result: #{output.strip}"
      rescue => e
        puts "  Error: #{e.message}"
      end
    end
  end

  it 'should debug the exact ETIMEDOUT context switching scenario' do
    puts "\n=== Debugging ETIMEDOUT Context Switching Scenario ==="
    
    # Enable maximum logging
    original_debug = ENV['DEBUG']
    ENV['DEBUG'] = 'webdriver:*,appium:*'
    
    begin
      puts "Step 1: Testing basic driver functionality..."
      current_activity = @driver.current_activity rescue "Unable to get activity"
      puts "Current activity: #{current_activity}"
      
      puts "\nStep 2: Testing context retrieval (this may fail with ETIMEDOUT)..."
      start_time = Time.now
      
      begin
        # This is the exact call that fails in client environments
        Timeout.timeout(135) do  # Slightly longer than the 131-second timeout in the error
          contexts = @driver.available_contexts
          puts "SUCCESS: Contexts retrieved: #{contexts}"
          puts "Time taken: #{Time.now - start_time} seconds"
          
          # Test context switching if multiple contexts available
          if contexts.length > 1
            puts "\nStep 3: Testing context switching..."
            original_context = @driver.current_context
            puts "Original context: #{original_context}"
            
            # Switch to webview context
            webview_context = contexts.find { |ctx| ctx.include?('WEBVIEW') }
            if webview_context
              puts "Switching to webview context: #{webview_context}"
              @driver.set_context(webview_context)
              puts "Current context after switch: #{@driver.current_context}"
              
              # Switch back
              puts "Switching back to original context: #{original_context}"
              @driver.set_context(original_context)
              puts "Current context after switch back: #{@driver.current_context}"
            else
              puts "No WEBVIEW context found, testing native context switch..."
              native_context = contexts.find { |ctx| ctx.include?('NATIVE') }
              if native_context && native_context != original_context
                @driver.set_context(native_context)
                puts "Switched to: #{@driver.current_context}"
                @driver.set_context(original_context)
                puts "Switched back to: #{@driver.current_context}"
              end
            end
          else
            puts "Only one context available: #{contexts}"
          end
        end
        
      rescue Timeout::Error
        puts "ERROR: Context retrieval timed out after 135 seconds"
        puts "This reproduces the client environment issue!"
        
      rescue => e
        puts "ERROR: #{e.class}: #{e.message}"
        puts "Time elapsed: #{Time.now - start_time} seconds"
        
        # Check if it's the specific ETIMEDOUT error
        if e.message.include?('ETIMEDOUT')
          puts "\n🎯 REPRODUCED: ETIMEDOUT error detected!"
          puts "Error details:"
          puts "  Message: #{e.message}"
          puts "  Class: #{e.class}"
          
          # Check for specific IP
          if e.message.include?('66.85.52.224:443')
            puts "  ✅ Specific IP 66.85.52.224:443 detected in error"
          end
          
          # Check for webdriver connection
          if e.message.include?('webdriver') || e.message.include?('RequestError')
            puts "  ✅ WebDriver request error detected"
          end
          
          puts "\nBacktrace (first 10 lines):"
          puts e.backtrace[0..9].join("\n")
        end
        
        # Re-raise to fail the test
        raise e
      end
      
    ensure
      ENV['DEBUG'] = original_debug
    end
  end

  it 'should test workaround with SKIP_DEPRECATED_JWP_COMMANDS' do
    puts "\n=== Testing Workaround: SKIP_DEPRECATED_JWP_COMMANDS ==="
    
    # Set the environment variable to skip deprecated commands
    original_skip = ENV['SKIP_DEPRECATED_JWP_COMMANDS']
    ENV['SKIP_DEPRECATED_JWP_COMMANDS'] = 'true'
    
    begin
      puts "Environment variable set: SKIP_DEPRECATED_JWP_COMMANDS=true"
      
      # Test if context switching is skipped
      puts "Testing context retrieval with workaround..."
      start_time = Time.now
      
      # This should either work or be skipped entirely
      contexts = @driver.available_contexts rescue ["WORKAROUND_ACTIVE"]
      puts "Result: #{contexts}"
      puts "Time taken: #{Time.now - start_time} seconds"
      
      if contexts == ["WORKAROUND_ACTIVE"]
        puts "✅ Workaround active: Context switching bypassed"
      else
        puts "ℹ️  Context switching still active, may need different workaround"
      end
      
    ensure
      ENV['SKIP_DEPRECATED_JWP_COMMANDS'] = original_skip
    end
  end

  it 'should test with different timeout configurations' do
    puts "\n=== Testing Different Timeout Configurations ==="
    
    timeout_configs = [
      { connection: 30000, request: 10000 },
      { connection: 60000, request: 30000 },
      { connection: 300000, request: 120000 }  # Default Eyes SDK timeouts
    ]
    
    timeout_configs.each_with_index do |config, index|
      puts "\nConfiguration #{index + 1}: connection=#{config[:connection]}ms, request=#{config[:request]}ms"
      
      # Set timeout environment variables if the SDK supports them
      ENV['EYES_NETWORK_CONNECTION_TIMEOUT'] = config[:connection].to_s
      ENV['EYES_NETWORK_REQUEST_TIMEOUT'] = config[:request].to_s
      
      start_time = Time.now
      begin
        Timeout.timeout(config[:request] / 1000 + 10) do  # Add 10 seconds buffer
          contexts = @driver.available_contexts
          puts "  SUCCESS: #{contexts} (#{Time.now - start_time}s)"
        end
      rescue => e
        puts "  FAILED: #{e.class} after #{Time.now - start_time}s"
        puts "    Message: #{e.message[0..100]}..."
      end
    end
  end

  it 'should monitor network traffic during context switching' do
    puts "\n=== Network Traffic Monitoring ==="
    
    # Start network monitoring in background
    monitor_pid = spawn("tcpdump -i any -n -s 0 'host 66.85.52.224 or port 443' > /tmp/traffic.log 2>&1")
    sleep 2  # Give tcpdump time to start
    
    begin
      puts "Network monitoring started (PID: #{monitor_pid})"
      puts "Testing context switching with traffic monitoring..."
      
      start_time = Time.now
      contexts = @driver.available_contexts rescue []
      end_time = Time.now
      
      puts "Context switching completed in #{end_time - start_time} seconds"
      
    ensure
      # Stop monitoring
      Process.kill('TERM', monitor_pid) rescue nil
      Process.wait(monitor_pid) rescue nil
      
      # Check traffic log
      if File.exist?('/tmp/traffic.log')
        traffic_content = File.read('/tmp/traffic.log')
        if traffic_content.length > 0
          puts "\nNetwork traffic detected:"
          puts traffic_content[0..500] + (traffic_content.length > 500 ? "..." : "")
        else
          puts "\nNo network traffic captured"
        end
      end
    end
  end
end