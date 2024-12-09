# Create an isolated network
docker network create --driver bridge isolated-test-net

# Create a proxy container (e.g., using Squid)
docker run -d --name test-proxy \
  --network isolated-test-net \
  -p 3128:3128 \
  ubuntu/squid

# Build and run the container
docker build -t appium-proxy-test .
docker run --rm \
  --network isolated-test-net \
  -v $(pwd)/logs:/app/logs \
  -e SAUCE_USERNAME \
  -e SAUCE_ACCESS_KEY \
  -e SAUCE_TUNNEL_ID \
  -e SAUCE_SERVER_URL \
  -e APP_APK_URL \
  -e APPLITOOLS_API_KEY \
  appium-proxy-test \
  bundle exec rspec spec/test_appium_proxy.rb --format documentation