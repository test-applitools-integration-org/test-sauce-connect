import os
import pytest
from appium import webdriver
from applitools.selenium import Eyes, Target
from spec_helper import SauceTunnel

# Environment variables
SAUCE_USERNAME = os.environ["SAUCE_USERNAME"]
SAUCE_ACCESS_KEY = os.environ["SAUCE_ACCESS_KEY"]
SAUCE_CONNECT_BIN = os.environ["SAUCE_CONNECT_BIN"]
SAUCE_TUNNEL_ID = os.environ["SAUCE_TUNNEL_ID"]
SAUCE_SERVER_URL = os.environ["SAUCE_SERVER_URL"]
APP_APK_URL = os.environ["APP_APK_URL"]
APPLITOOLS_PROXY_URL = os.getenv("APPLITOOLS_PROXY_URL")


@pytest.fixture(scope="session")
def sauce_tunnel():
    print("Setting up Sauce Connect tunnel...")
    tunnel = SauceTunnel(
        username=SAUCE_USERNAME,
        access_key=SAUCE_ACCESS_KEY,
        sc_path=SAUCE_CONNECT_BIN,
        tunnel_name=SAUCE_TUNNEL_ID,
        dns=False,
        no_ssl_bump_domains=None,
        proxy=APPLITOOLS_PROXY_URL,
    )
    tunnel.start()
    yield tunnel
    print("Tearing down Sauce Connect tunnel...")
    tunnel.terminate()


@pytest.fixture(scope="function")
def appium_driver():
    print("Setting up test environment...")

    capabilities = {
        "deviceName": "Samsung Galaxy S8 FHD GoogleAPI Emulator",
        "platformName": "Android",
        "platformVersion": "7.0",
        "app": APP_APK_URL,
        "appium:automationName": "UIAutomator2",
    }

    sauce_options = {
        "name": "test_appium_proxy",
        "username": SAUCE_USERNAME,
        "accessKey": SAUCE_ACCESS_KEY,
    }

    if SAUCE_TUNNEL_ID:
        sauce_options["tunnelName"] = SAUCE_TUNNEL_ID

    capabilities["sauce:options"] = sauce_options


    driver = webdriver.Remote(command_executor=SAUCE_SERVER_URL, desired_capabilities=capabilities)

    yield driver

    print("Cleaning up test environment...")
    if driver:
        driver.quit()


@pytest.fixture(scope="function")
def eyes():
    eyes = Eyes()
    eyes.configure.app_name = "Applitools Eyes SDK"
    eyes.configure.test_name = "Test Appium Sauce Connect Proxy"
    eyes.set_proxy(APPLITOOLS_PROXY_URL)
    return eyes


@pytest.mark.sauce
def test_appium_proxy(sauce_tunnel, appium_driver, eyes):
    print("Running Appium proxy test...")
    eyes.open(driver=appium_driver)
    eyes.check("Window Check", Target.window().fully())
    results = eyes.close(raise_ex=True)
    print(results)
