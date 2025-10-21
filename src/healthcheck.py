#!/usr/bin/env python3
import sys
import requests
import time


def health_check(host="localhost", port=8000, timeout=5, max_retries=3):
    url = f"http://{host}:{port}/health"

    for attempt in range(max_retries):
        try:
            response = requests.get(url, timeout=timeout)

            if response.status_code == 200:
                data = response.json()
                if data.get("status") == "healthy":
                    print(f"API is healthy (attempt {attempt + 1}/{max_retries})")
                    return True
                else:
                    print(f"API returned unhealthy status: {data}")

            else:
                print(f"❌ API returned status code: {response.status_code}")

        except requests.exceptions.ConnectionError:
            print(f"Connection failed (attempt {attempt + 1}/{max_retries})")
        except requests.exceptions.Timeout:
            print(f"Request timed out (attempt {attempt + 1}/{max_retries})")
        except requests.exceptions.RequestException as e:
            print(f"❌ Request error: {e}")
        except Exception as e:
            print(f"❌ Unexpected error: {e}")

        if attempt < max_retries - 1:
            time.sleep(2)

    print(f"❌ Health check failed after {max_retries} attempts")
    return False


def main():
    host = sys.argv[1] if len(sys.argv) > 1 else "localhost"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8000

    is_healthy = health_check(host, port)

    sys.exit(0 if is_healthy else 1)


if __name__ == "__main__":
    main()
