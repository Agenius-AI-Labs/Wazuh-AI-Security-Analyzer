"""
Wazuh rule 5712 trigger test.

Fires N failed SSH password-auth attempts against a target host to simulate
a brute-force attack. The Wazuh agent on the target reports each failure;
the Wazuh manager correlates them and emits a level-10 alert which feeds the
Wazuh AI Security Analyzer n8n workflow.

Authorized defensive test only. Target must be infrastructure you operate.

Usage:
    python wazuh-bruteforce-test.py <target_ip> [--user fakeuser] [--count 10]
"""
import argparse
import sys
import time

try:
    import paramiko
except ImportError:
    print("paramiko not installed. Run: pip install paramiko", file=sys.stderr)
    sys.exit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("target", help="Target IP or hostname (must be authorized)")
    ap.add_argument("--user", default="bf_test_user", help="Bogus username")
    ap.add_argument("--count", type=int, default=10, help="Number of failed attempts")
    ap.add_argument("--delay", type=float, default=0.8, help="Seconds between attempts")
    args = ap.parse_args()

    print(f"[*] Target: {args.target}")
    print(f"[*] User:   {args.user}")
    print(f"[*] Count:  {args.count} attempts ({args.delay}s apart)")
    print(f"[*] Wazuh rule 5712 threshold: 6 failures in 120s")
    print()

    failures = 0
    for i in range(1, args.count + 1):
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        try:
            client.connect(
                hostname=args.target,
                username=args.user,
                password=f"WrongPassword{i}",
                timeout=5,
                allow_agent=False,
                look_for_keys=False,
            )
            print(f"[{i:>2}] UNEXPECTED SUCCESS, aborting.")
            client.close()
            sys.exit(2)
        except paramiko.AuthenticationException:
            failures += 1
            print(f"[{i:>2}] auth failed (expected)")
        except Exception as e:
            print(f"[{i:>2}] error: {e}")
        finally:
            client.close()
        time.sleep(args.delay)

    print()
    print(f"[+] Done. {failures}/{args.count} failed auth attempts logged on {args.target}.")
    print(f"[+] Wazuh manager should emit rule 5712 alert within ~30s.")
    print(f"[+] Watch the Slack security channel for the AI-analyzed message.")


if __name__ == "__main__":
    main()
