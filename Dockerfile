FROM ruby:3.1

# Install required packages
RUN apt-get update && apt-get install -y build-essential curl unzip && rm -rf /var/lib/apt/lists/*

# Install Sauce Connect
RUN curl -L -o /tmp/sauce-connect.deb \
    https://saucelabs.com/downloads/sauce-connect/5.2.2/sauce-connect_5.2.2.linux_amd64.deb && \
    dpkg -i /tmp/sauce-connect.deb && \
    rm -f /tmp/sauce-connect.deb

ENV SAUCE_CONNECT_BIN=/usr/bin/sc
ENV APPLITOOLS_LOG_DIR=./logs
ENV APPLITOOLS_PROXY_URL="http://test-proxy:3128"

# Set working directory
WORKDIR /app

# Copy test files
COPY spec ./spec/
COPY Gemfile .

# Install dependencies
RUN gem install bundler
RUN bundle install

