# Universal SDK Binary Inspector
# Analyzes the Eyes Universal SDK binary to understand its configuration and capabilities

require 'json'
require 'open3'

class UniversalSDKInspector
  def self.inspect_binary
    puts "=== Universal SDK Binary Inspection ==="
    
    # Find the gem path
    gem_spec = find_eyes_gem
    return unless gem_spec
    
    gem_path = gem_spec.full_gem_path
    puts "Eyes gem path: #{gem_path}"
    puts "Eyes gem version: #{gem_spec.version}"
    
    # Look for Universal SDK binaries
    binary_paths = find_universal_binaries(gem_path)
    
    if binary_paths.empty?
      puts "❌ No Universal SDK binaries found"
      return
    end
    
    binary_paths.each do |binary_path|
      inspect_binary_file(binary_path)
    end
    
    # Test proxy environment detection
    test_proxy_environment_detection
  end
  
  private
  
  def self.find_eyes_gem
    # Try different gem names that might contain the Universal SDK
    gem_names = ['eyes_appium', 'eyes_universal', 'eyes_selenium', 'eyes_core']
    
    gem_names.each do |gem_name|
      begin
        spec = Gem.loaded_specs[gem_name]
        if spec
          puts "Found gem: #{gem_name} (#{spec.version})"
          return spec
        end
      rescue => e
        puts "Gem #{gem_name} not found: #{e.message}"
      end
    end
    
    # Try to find any gem with eyes-universal in it
    Gem.loaded_specs.each do |name, spec|
      if name.include?('eyes') || spec.full_gem_path.include?('eyes-universal')
        puts "Found potential gem: #{name} (#{spec.version})"
        return spec
      end
    end
    
    puts "❌ No Eyes SDK gems found in loaded specs"
    nil
  end
  
  def self.find_universal_binaries(gem_path)
    binary_paths = []
    
    # Common Universal SDK binary locations
    search_patterns = [
      File.join(gem_path, 'ext', 'eyes-universal', 'core-*'),
      File.join(gem_path, 'lib', 'eyes-universal', 'core-*'),
      File.join(gem_path, 'bin', 'core-*'),
      File.join(gem_path, '**', 'core-*')
    ]
    
    search_patterns.each do |pattern|
      Dir.glob(pattern).each do |path|
        if File.executable?(path)
          binary_paths << path
          puts "Found binary: #{path}"
        end
      end
    end
    
    binary_paths
  end
  
  def self.inspect_binary_file(binary_path)
    puts "\n--- Inspecting Binary: #{File.basename(binary_path)} ---"
    
    # Check file type
    file_output, status = Open3.capture2('file', binary_path)
    puts "File type: #{file_output.strip}"
    
    # Check if it's a Node.js Single Executable Application (SEA)
    if file_output.include?('ELF') || file_output.include?('executable')
      puts "Binary type: Native executable"
      
      # Try to get version info
      version_commands = ['--version', '-v', '--help', '-h']
      version_commands.each do |cmd|
        begin
          output, status = Open3.capture2e(binary_path, cmd, timeout: 10)
          if status.success? && !output.empty?
            puts "Version info (#{cmd}): #{output.strip[0..200]}"
            break
          end
        rescue => e
          # Ignore errors, try next command
        end
      end
      
      # Check for embedded Node.js (SEA detection)
      strings_output, status = Open3.capture2('strings', binary_path)
      if strings_output.include?('node') || strings_output.include?('NODE_')
        puts "Detected: Node.js Single Executable Application (SEA)"
        
        # Look for specific indicators
        indicators = ['webdriver', 'proxy', 'HTTP_PROXY', 'undici', 'node_modules']
        indicators.each do |indicator|
          if strings_output.include?(indicator)
            puts "  Found indicator: #{indicator}"
          end
        end
        
        # Check for webdriver version
        if match = strings_output.match(/webdriver.*version.*(\d+\.\d+\.\d+)/)
          puts "  WebDriver version: #{match[1]}"
        end
      end
      
      # Test if binary accepts proxy environment variables
      test_binary_proxy_support(binary_path)
    end
    
    # Check file size
    file_size = File.size(binary_path)
    puts "File size: #{file_size} bytes (#{file_size / 1024 / 1024}MB)"
    
    # Check permissions
    file_stat = File.stat(binary_path)
    puts "Permissions: #{sprintf('%o', file_stat.mode)}"
    puts "Executable: #{File.executable?(binary_path)}"
  end
  
  def self.test_binary_proxy_support(binary_path)
    puts "\n  Testing binary proxy support..."
    
    # Test with different proxy environment variables
    proxy_envs = {
      'HTTP_PROXY' => 'http://test-proxy:3128',
      'HTTPS_PROXY' => 'http://test-proxy:3128',
      'WEBDRIVER_HTTP_PROXY' => 'http://test-proxy:3128',
      'WEBDRIVER_HTTPS_PROXY' => 'http://test-proxy:3128'
    }
    
    proxy_envs.each do |env_var, proxy_url|
      begin
        # Run binary with proxy environment variable set
        env = {env_var => proxy_url}
        output, status = Open3.capture2e(env, binary_path, '--help', timeout: 5)
        
        # Check if the binary runs without proxy-related errors
        if status.success?
          puts "    ✅ #{env_var}: Binary accepts environment variable"
        else
          puts "    ❌ #{env_var}: Binary failed with exit code #{status.exitstatus}"
        end
      rescue => e
        puts "    ❓ #{env_var}: Test failed - #{e.message}"
      end
    end
  end
  
  def self.test_proxy_environment_detection
    puts "\n=== Proxy Environment Detection ==="
    
    # Test current environment
    proxy_vars = ['HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy', 'ALL_PROXY']
    proxy_vars.each do |var|
      value = ENV[var]
      if value
        puts "✅ #{var}: #{value}"
      else
        puts "❌ #{var}: not set"
      end
    end
    
    # Test Ruby's proxy detection
    begin
      require 'net/http'
      uri = URI('https://www.google.com')
      http = Net::HTTP.new(uri.host, uri.port)
      puts "\nRuby Net::HTTP proxy detection:"
      puts "  Proxy address: #{http.proxy_address || 'none'}"
      puts "  Proxy port: #{http.proxy_port || 'none'}"
    rescue => e
      puts "Ruby proxy detection failed: #{e.message}"
    end
  end
end

# Require this file in spec_helper.rb to make the class available