# Appium Sauce Connect Proxy

## Prerequisites

Before running the tests, ensure you have the following installed:
- Ruby (recommended version 2.7 or higher)
- Bundler gem
- SauceLabs account
- Applitools account
- Sauce Connect Proxy

### Verify Sauce Connect Installation

1. Download Sauce Connect from [SauceLabs Official Website](https://docs.saucelabs.com/secure-connections/sauce-connect/installation/)

2. Verify the installation:
```bash
sc version
```

3. Make sure to note the path to your Sauce Connect binary as you'll need it for the `SAUCE_CONNECT_BIN` environment variable.

## Installation

1. Clone this repository:
```bash
git clone https://github.com/test-applitools-integration-org/test-sauce-connect.git
cd test-sauce-connect
```

2. Install dependencies:
```bash
bundle install
```

3. Set up environment variables:
```bash
cp .envrc.example .envrc
```

4. Configure the following environment variables in `.envrc`:

```bash
export SAUCE_SERVER_URL="https://ondemand.us-west-1.saucelabs.com:443/wd/hub"
export SAUCE_TUNNEL_ID="applitools-proxy-test"
export APPLITOOLS_LOG_DIR="./logs"

# SauceLabs credentials
export SAUCE_USERNAME="your-username"
export SAUCE_ACCESS_KEY="your-access-key"
export SAUCE_CONNECT_BIN="/path/to/sc-binary"

# Application APK
export APP_APK_URL="your-app-url"

# Applitools configuration
export APPLITOOLS_API_KEY="your-api-key"
export APPLITOOLS_SERVER_URL="your-server-url"
export APPLITOOLS_PROXY_URL="your-proxy-url"
```

5. Load the environment variables:
```bash
source .envrc
```

## Running Tests

1. Ensure that all env variables are properly configured.

2. Run the tests using RSpec:
```bash
bundle exec rspec spec/test_appium_proxy.rb
```