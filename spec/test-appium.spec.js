const wdio = require('webdriverio')
const {Eyes, Target} = require('@applitools/eyes-webdriverio')
const {spawn} = require('child_process')
const { setGlobalDispatcher, ProxyAgent } = require('undici');

const dispatcher = new ProxyAgent({ uri: new URL(process.env.APPLITOOLS_PROXY_URL).toString() });
setGlobalDispatcher(dispatcher);

const capabilities = {
  platformName: 'Android',
  'appium:app': "sauce-storage:SimpleApp.apk",
  'appium:deviceName': 'Google Pixel 4 GoogleAPI Emulator',
  'appium:platformVersion': '14',
  'appium:automationName': 'UiAutomator2',
  'appium:appPackage': 'com.applitools.simpleapp',
  'appium:appActivity': 'com.applitools.simpleapp.CardViewsActivity',
  'appium:optionalIntentArguments': `--es APPLITOOLS '{"APPLITOOLS_API_KEY": "${process.env.APPLITOOLS_API_KEY}"}'`,
  'appium:newCommandTimeout': 300,
  'appium:idleTimeout': 300,
  "sauce:options": {
    name: "ido-test",
    username: process.env.SAUCE_USERNAME,
    accessKey: process.env.SAUCE_ACCESS_KEY,
    tunnelName: 'applitools-proxy-test'
  }
}

describe('proxy', function() {
  let driver
  let sc

  this.timeout(0)

  before(async () => {
    await startSauceConnect()
    console.log('sauce connect started');
  })

  beforeEach(async () => {
    driver = await wdio.remote({
      automationProtocol: 'webdriver',
      capabilities,
      hostname: 'ondemand.us-west-1.saucelabs.com',
      port: 443,
      protocol: 'https',
      path: '/wd/hub'
    })
    console.log('sauce driver created');
  })

  after(async () => {
    await driver?.deleteSession()

    if (sc) {
      sc.kill('SIGTERM')
      console.log('SauceConnect closed')
    }
  })

  it('test proxy', async () => {

    const eyes = new Eyes()
    await eyes.open(driver, 'pac proxy', 'pac proxy')
    await eyes.check({
      fully: false,
    })
    await eyes.close()
  })

  async function startSauceConnect() {
    return new Promise((resolve, reject) => {
      const sauceConnectArgsLegacy = [
        'legacy',
        '-u', process.env.SAUCE_USERNAME,
        '-k', process.env.SAUCE_ACCESS_KEY,
        '--region', 'us-west',
        '--tunnel-name', 'applitools-proxy-test',
        '--proxy', process.env.APPLITOOLS_PROXY_URL, '--proxy-tunnel',
        '--status-address', 'localhost:8989',
        '--verbose',
        '--no-autodetect',
        //'--logfile', 'logs/sc.log',
        // ... any other Sauce Connect arguments you need (e.g., --region, --proxy, etc.)
      ];

      const sauceConnectArgs = [
        'run',
        '--username', process.env.SAUCE_USERNAME,
        '--access-key', process.env.SAUCE_ACCESS_KEY,
        '--region', 'us-west',
        '--tunnel-name', 'applitools-proxy-test',
        '--proxy', process.env.APPLITOOLS_PROXY_URL,
        '--proxy-localhost', 'allow',
        //'--status-address', 'localhost:8989',
        // '--logfile', 'logs/sc.log',
        // '--verbose',
        // ... any other Sauce Connect arguments you need (e.g., --region, --proxy, etc.)
      ];

      const scBinPath = process.env.SAUCE_CONNECT_BIN || '/usr/local/bin//sc'

      sc = spawn(scBinPath, sauceConnectArgsLegacy)

      const readyListener = (data) => {
        const output = data.toString()
        console.log('stdout:', output)
        if (output.includes('Sauce Connect is up, you may start your tests')) {
          resolve()
        }
      }

      sc.stdout.on('data', readyListener)

      sc.stderr.on('data', data => {
        console.log('stderr:', data.toString())
      })

      sc.on('error', reject)
      sc.on('exit', code => {
        if (code !== 0) reject(new Error(`Sauce Connect exited with code ${code}`))
      })
    })

  }
})