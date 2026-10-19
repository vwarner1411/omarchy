#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"
require_command python3

python3 <<'PY'
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import time
import unittest

loader = importlib.machinery.SourceFileLoader(
  "codex_collector", os.environ["ROOT"] + "/bin/omarchy-agent-usage-codex"
)
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

SERVER = '''
import json,os,sys,time
request = json.loads(sys.stdin.readline())
chunks = json.loads(sys.argv[1])
for chunk in chunks:
  os.write(1, chunk.encode())
  time.sleep(0.01)
time.sleep(0.4)
'''
REPLY = {"id": 2, "result": {"account": {"type": "chatgpt"}}}
NOTIFICATION = {"method": "account/updated", "params": {"authMode": "chatgpt"}}


class CodexRpcTests(unittest.TestCase):
  def request(self, chunks, timeout=0.15):
    proc = subprocess.Popen(
      [sys.executable, "-u", "-c", SERVER, json.dumps(chunks)],
      stdin=subprocess.PIPE, stdout=subprocess.PIPE,
      stderr=subprocess.DEVNULL, text=True,
    )
    try:
      return collector.rpc_request(proc, 2, "account/read", timeout=timeout)
    finally:
      proc.terminate()
      proc.wait(timeout=2)
      proc.stdin.close()
      proc.stdout.close()

  def test_plain_reply(self):
    self.assertEqual(self.request([json.dumps(REPLY) + "\n"]), REPLY)

  def test_notification_and_reply_in_one_write(self):
    combined = json.dumps(NOTIFICATION) + "\n" + json.dumps(REPLY) + "\n"
    for _ in range(10):
      self.assertEqual(self.request([combined]), REPLY)

  def test_split_json_reply(self):
    wire = json.dumps(REPLY) + "\n"
    self.assertEqual(self.request([wire[:8], wire[8:20], wire[20:]]), REPLY)

  def test_other_messages_in_one_write(self):
    wire = "not json\n[]\n" + json.dumps({"id": 99, "result": {}}) + "\n"
    self.assertEqual(self.request([wire + json.dumps(REPLY) + "\n"]), REPLY)

  def test_server_error_remains_an_error_reply(self):
    error = {"id": 2, "error": {"code": -32000, "message": "Unavailable"}}
    self.assertEqual(self.request([json.dumps(error) + "\n"]), error)

  def test_partial_line_does_not_block_past_deadline(self):
    started = time.monotonic()
    with self.assertRaisesRegex(TimeoutError, "account/read"):
      self.request(['{"id":2'], timeout=0.1)
    self.assertLess(time.monotonic() - started, 0.35)

  def test_no_reply_still_times_out(self):
    with self.assertRaisesRegex(TimeoutError, "account/read"):
      self.request([], timeout=0.1)


unittest.main(verbosity=2)
PY
