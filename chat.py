"""Console chat client for the serverless Repo Digest agent.

Sends prompts to the built-in chat endpoint exposed by the ``main`` agent and prints
the response. Set AGENT_URL to target a deployed function app and FUNCTION_KEY when the
endpoint requires a function key.
"""
import json
import os
import urllib.request

BASE_URL = os.environ.get("AGENT_URL", "http://localhost:7071").rstrip("/")
FUNCTION_KEY = os.environ.get("FUNCTION_KEY", "")
CHAT_URL = f"{BASE_URL}/agents/main/chat"

print("=== Repo Digest Agent Chat ===")
print(f"Endpoint: {CHAT_URL}")
print("Try: Create a concise repo digest for Azure/azure-functions-host.")
print("Type 'exit' or 'quit' to end.\n")

session_id = None

while True:
    message = input("You: ").strip()
    if not message or message.lower() in ("exit", "quit"):
        print("Goodbye!")
        break

    payload = {"prompt": message}
    if session_id:
        payload["session_id"] = session_id

    headers = {"Content-Type": "application/json"}
    if FUNCTION_KEY:
        headers["x-functions-key"] = FUNCTION_KEY

    try:
        req = urllib.request.Request(
            CHAT_URL,
            data=json.dumps(payload).encode(),
            headers=headers,
            method="POST",
        )
        with urllib.request.urlopen(req) as resp:
            response = json.loads(resp.read().decode())
        session_id = response.get("session_id", session_id)
        print(f"\nAgent: {response.get('response') or json.dumps(response)}\n")
    except Exception as e:
        print(f"\nError: {e}\n")
