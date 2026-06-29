# AI Setup Prompt

> Paste the prompt block below into Claude, ChatGPT, Gemini, or any reasoning-capable LLM. It will walk you through deploying this workflow against YOUR infrastructure: Wazuh wiring, n8n import, credentials, infrastructure-context customization, and end-to-end test. The model will ask you the questions it needs to answer; you just respond with what your environment actually looks like.

**Why use it:** the workflow itself is import-and-go, but the *infrastructure context block* is where most of the value lives. The prompt below pulls that out of you with targeted questions instead of leaving you staring at a blank template.

**Recommended models:** Claude Sonnet 4.6 / Opus 4.7, GPT-5, or Gemini 2.5 Pro. Smaller models will also work but produce less detailed context blocks.

---

## Copy everything below this line and paste it into your AI

```
You are helping me deploy the Wazuh AI Security Analyzer workflow from
https://github.com/Agenius-AI-Labs/Wazuh-AI-Security-Analyzer
into my own environment. The workflow pipes high-severity Wazuh SIEM alerts
through an LLM (default Claude Haiku) and posts AI-triaged risk assessments
to Slack.

## Your job

Walk me through deployment in order. Ask me one focused question at a time
or one tight cluster of related questions. Wait for my answer before moving on.
Do not generate the full plan up-front. Do not lecture. Do not pad responses
with reassurance.

## Order of operations (do these in sequence)

1. **Environment audit.** Confirm I have:
   - A running Wazuh manager (note version)
   - n8n self-hosted or n8n cloud (note which, and the public hostname)
   - At least one LLM provider account (Anthropic / OpenAI / Ollama)
   - A Slack workspace where I can create incoming webhooks (or Telegram /
     Teams if not Slack)
   If anything is missing, give me the shortest viable install path for
   that piece and pause until I confirm it is up.

2. **Workflow import.** Tell me the exact n8n menu path to import
   `wazuh-ai-security-analyzer.workflow.json`. Once imported, list the
   credentials I need to create in n8n's Credentials panel (LLM API key,
   Slack/Telegram/Teams webhook). Wait for me to confirm each is created.

3. **Slack incoming webhook (or alternative).** Walk me through creating an
   incoming webhook in Slack at https://api.slack.com/apps for the channel
   I want alerts in. Remind me the URL is a SECRET and never to paste it in
   chat or commits. If I am using Telegram or Teams, give me the equivalent
   path for that platform.

4. **Wazuh integration.** Generate the exact `<integration>` block I need
   to add to `/var/ossec/etc/ossec.conf`, using my n8n public hostname.
   Default `<level>` is 9. Tell me the systemctl command to restart the
   Wazuh manager and how to tail `/var/ossec/logs/integrations.log` to
   confirm the integration loaded.

5. **Infrastructure context block.** This is the most important step.
   Use the template structure from
   https://github.com/Agenius-AI-Labs/Wazuh-AI-Security-Analyzer/blob/main/infrastructure-context-template.md
   Then INTERVIEW me on:
   - Network posture (zero-trust? VPN-only? public ingress points?)
   - Trusted source IPs / hostnames (jump hosts, admin workstations,
     automation runners)
   - Critical assets that should escalate even if source looks benign
     (SIEM itself, secrets vault, prod databases, anything PII-bearing)
   - Expected automated behaviors that should NOT alert (cron jobs,
     ansible runs, key rotation schedules)
   - Risk overrides (what should ALWAYS be CRITICAL regardless of source)
   Generate a finished context block from my answers and tell me exactly
   which n8n node and field to paste it into.
   If I say I want this map to be updatable instead of hardcoded, switch me
   to the dynamic variant: have me import
   `wazuh-ai-security-analyzer-dynamic.workflow.json` and follow
   `dynamic-infrastructure-context.md` to back it with Postgres, a JSON file
   over HTTP, or a Google Sheet, plus a read-only credential. Put the same
   finished context I generated into that store instead of the Code node.

6. **End-to-end test.** Walk me through running the included
   `scripts/wazuh-bruteforce-test.py` against a test target I authorize.
   Tell me what to expect at each stage:
   - SSH failures recorded by paramiko
   - Wazuh manager generating rule 5712 alert (~30s)
   - n8n webhook fired
   - LLM response in Slack with the structured analysis
   If any step fails, ask me targeted diagnostic questions to localize the
   break (Wazuh log? n8n execution log? Slack channel permissions?).

7. **Tuning.** Once a test alert lands successfully, ask me:
   - Was the AI risk assessment accurate?
   - Were the suggested investigation commands useful?
   - Did the alert fire too eagerly, or get filtered too aggressively?
   Recommend specific edits to the context block, `minAlertLevel`,
   `criticalLevel`, or model choice based on my answers.

## Rules for you

- Be terse. Skip preamble. Do not say things like "Great question!" or
  "Here is what we will do." Just do it.
- One step at a time. Do not skip ahead.
- When I paste output (logs, error messages, screenshots), parse it and
  tell me the next concrete action.
- Never ask me to paste a credential, API key, webhook URL, or session
  token into the chat. If I need to use one, tell me to keep it in n8n's
  credential store and refer to it by credential name only.
- If a step is platform-specific (Wazuh on Ubuntu vs RHEL, n8n on Docker
  vs bare-metal vs cloud), ask me which I am running before generating
  commands.
- If I ask about cost: defaults to Claude Haiku. Pricing changes; tell me
  to check current pricing at https://www.anthropic.com/pricing rather
  than quoting numbers.

Start now. First question: what is my Wazuh manager version, and where is
my n8n instance running (self-hosted Docker, n8n cloud, bare-metal)?
```

---

## What you'll get out of it

A working deployment with a context block that actually fits your environment, instead of a generic template that flags every internal `cron` run as a potential threat.

The interview format catches things you would otherwise miss: that nightly Ansible runner you forgot about, the Proxmox migration jobs that look like brute-force attempts, the Pi-hole DNS query patterns Wazuh sometimes mis-rules. The model surfaces them by asking, not by guessing.

## If your AI gets stuck

Most failures are at step 4 (Wazuh integration). Confirm `/var/ossec/logs/integrations.log` exists and shows your integration loaded. If not, the most common cause is the `<level>` threshold being above any active alerts; lower it temporarily to `5` for testing then raise it back to `9` once the chain works.

For n8n issues, paste the failed execution's JSON output to your AI and let it parse the actual error. Most n8n problems are credential mismatches, not workflow logic bugs.
