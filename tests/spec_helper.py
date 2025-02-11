import subprocess
import time
import os
import signal
import requests
from requests.exceptions import RequestException
import platform


class SauceTunnel:
    MAX_RETRIES = 5
    RETRY_INTERVAL = 8
    CONNECTION_TIMEOUT = 10

    def __init__(
        self,
        username: str,
        access_key: str,
        sc_path: str,
        tunnel_name: str,
        dns: bool,
        no_ssl_bump_domains: str | None,
        proxy: str,
    ):
        self.sauce_connect = None
        self.sc_path = sc_path
        self.tunnel_name = tunnel_name
        self.dns = dns
        self.no_ssl_bump_domains = no_ssl_bump_domains
        self.user = username
        self.access_key = access_key
        self.proxy = proxy

    def process_alive(self, pid: int) -> bool:
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False
        except PermissionError:
            return True

    def check_connection(self, readiness_url: str) -> bool:
        try:
            for _ in range(3):  # Retry logic
                try:
                    response = requests.get(
                        readiness_url, timeout=self.CONNECTION_TIMEOUT
                    )
                    if response.status_code == 200:
                        return response.json()["status"] == "connected"
                except (RequestException, ValueError) as e:
                    print(f"Connection attempt failed: {str(e)}")
                    time.sleep(1)
            return False
        except Exception as e:
            print(f"Connection check failed: {str(e)}")
            return False

    def wait_for_sc_readiness(self, timeout_seconds: int = 300) -> bool:
        readiness_url = "http://localhost:8989/status"
        start_time = time.time()
        attempt = 1

        while True:
            time_elapsed = time.time() - start_time
            if time_elapsed > timeout_seconds:
                raise TimeoutError(
                    f"Service readiness check timed out after {timeout_seconds} seconds"
                )

            print(f"Attempt {attempt} to check Sauce Connect status...")

            if self.check_connection(readiness_url):
                print("Sauce Connect established connection successfully")
                return True

            attempt += 1
            remaining_time = timeout_seconds - time_elapsed
            sleep_time = min(self.RETRY_INTERVAL, remaining_time)

            print(
                f"Retrying in {sleep_time} seconds... ({int(remaining_time)}s remaining)"
            )
            time.sleep(sleep_time)

    def start(self) -> None:
        for attempt in range(self.MAX_RETRIES):
            try:
                sc_command = [
                    self.sc_path,
                    "legacy",
                    "-u",
                    self.user,
                    "-k",
                    self.access_key,
                    "--region",
                    "us-west",
                    "--tunnel-name",
                    self.tunnel_name,
                    "--status-address",
                    "localhost:8989",
                    "--logfile",
                    "logs/sc.log",
                    "--verbose",
                ]
                if self.proxy:
                    sc_command.extend(["--proxy", self.proxy, "--proxy-tunnel"])
                if self.dns:
                    sc_command.extend(["--dns", self.dns])
                if self.no_ssl_bump_domains:
                    sc_command.extend(
                        ["--no-ssl-bump-domains", self.no_ssl_bump_domains]
                    )

                print("Starting Sauce Connect with command:")
                print(" ".join(str(c) for c in sc_command))

                if platform.system() == "Windows":
                    self.sauce_connect = subprocess.Popen(
                        " ".join(sc_command),
                        shell=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                    )
                else:
                    self.sauce_connect = subprocess.Popen(
                        sc_command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
                    )

                if self.wait_for_sc_readiness():
                    return
            except Exception as e:
                print(f"Attempt {attempt + 1} failed: {str(e)}")
                if attempt < self.MAX_RETRIES - 1:
                    time.sleep(2**attempt)  # Exponential backoff
                else:
                    raise

    def terminate(self) -> None:
        if self.sauce_connect:
            try:
                print("Terminating Sauce Connect tunnel")
                if platform.system() == "Windows":
                    self.sauce_connect.terminate()
                else:
                    os.kill(self.sauce_connect.pid, signal.SIGTERM)

                start_time = time.time()
                while time.time() - start_time < 10:
                    if not self.process_alive(self.sauce_connect.pid):
                        break
                    time.sleep(1)
                else:
                    print("Force killing Sauce Connect tunnel")
                    if platform.system() == "Windows":
                        self.sauce_connect.kill()
                    else:
                        os.kill(self.sauce_connect.pid, signal.SIGKILL)

            except ProcessLookupError as e:
                print(f"Process already terminated: {str(e)}")
            except Exception as e:
                print(f"Error during termination: {str(e)}")
            finally:
                self.sauce_connect = None
