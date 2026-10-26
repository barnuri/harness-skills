#!/usr/bin/env python3
"""Audit one Claude Code session transcript: user requests, background work, and agent-spec state files."""

import argparse
import glob
import json
import os
import re
import sys
from dataclasses import dataclass, field

PREVIEW_CHARS = 240
SYSTEM_REMINDER = re.compile(r"<system-reminder>.*?</system-reminder>", re.DOTALL)
COMMAND_NAME = re.compile(r"<command-name>(.*?)</command-name>", re.DOTALL)
COMMAND_ARGS = re.compile(r"<command-args>(.*?)</command-args>", re.DOTALL)
TASK_ID = re.compile(r"<task-id>(.*?)</task-id>")
TASK_STATUS = re.compile(r"<status>(.*?)</status>")
BACKGROUND_ID = re.compile(r"running in background with ID: (\S+?)\.")
MONITOR_ID = re.compile(r"Monitor started \(task (\S+?),")
AGENT_ID = re.compile(r"agentId: (\S+?) ")
STOPPED_ID = re.compile(r"Successfully stopped task: (\S+)")
AGENT_SPEC_DIR = re.compile(r"(?:~|/)[^\s'\"`]*/agent-spec/[^\s'\"`/]+")
ENDED_STATUSES = {"completed", "failed", "killed", "stopped", "cancelled"}
EDIT_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}
TASK_MARKERS = {"open": "- [ ]", "in progress": "- 🔄", "blocked": "- ⏸", "done": "- [x]"}
REVIEW_MARKERS = ["❌ Open", "🆕 New", "📤 Reported", "✅ Fixed"]


@dataclass
class BackgroundTask:
    task_id: str
    kind: str
    description: str
    launched_at: str
    ended: str = ""


@dataclass
class Audit:
    messages: list = field(default_factory=list)
    tasks: dict = field(default_factory=dict)
    spec_dirs: set = field(default_factory=set)


def find_transcript(session_id: str) -> str:
    matches = glob.glob(os.path.expanduser(f"~/.claude/projects/*/{session_id}.jsonl"))
    if not matches:
        sys.exit(f"No transcript named {session_id}.jsonl was found under ~/.claude/projects.")
    return max(matches, key=os.path.getmtime)


def text_of(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(
            block.get("text", "") for block in content if isinstance(block, dict) and block.get("type") == "text"
        )
    return ""


def request_text(raw: str) -> str:
    """The user's own words of a prompt; empty for harness notifications."""
    text = SYSTEM_REMINDER.sub("", raw).strip()
    if not text or text.startswith("<task-notification>") or text.startswith("<local-command"):
        return ""
    command = COMMAND_NAME.search(text)
    if command:
        args = COMMAND_ARGS.search(text)
        return f"{command.group(1).strip()} {args.group(1).strip() if args else ''}".strip()
    return " ".join(text.split())


def record_notifications(audit: Audit, raw: str) -> None:
    for block in raw.split("<task-notification>")[1:]:
        task_id = TASK_ID.search(block)
        status = TASK_STATUS.search(block)
        if not task_id:
            continue
        task = audit.tasks.get(task_id.group(1))
        ended_by_status = status and status.group(1).strip() in ENDED_STATUSES
        if task and (ended_by_status or "stream ended" in block):
            task.ended = status.group(1).strip() if ended_by_status else "stream ended"


def record_message(audit: Audit, timestamp: str, raw: str, source: str) -> None:
    record_notifications(audit, raw)
    text = request_text(raw)
    if text and all(text != seen for _, seen, _ in audit.messages):
        audit.messages.append((timestamp, text, source))


def record_tool_use(audit: Audit, block: dict, launches: dict) -> None:
    name = block.get("name", "")
    tool_input = block.get("input", {}) or {}
    touched = tool_input.get("file_path") if name in EDIT_TOOLS else tool_input.get("command") if name == "Bash" else ""
    for folder in AGENT_SPEC_DIR.findall(str(touched or "")):
        audit.spec_dirs.add(os.path.expanduser(folder))
    background = (name == "Bash" and tool_input.get("run_in_background")) or name in ("Monitor", "Agent")
    if background:
        launches[block.get("id")] = (name, str(tool_input.get("description", ""))[:80])


def record_tool_result(audit: Audit, block: dict, timestamp: str, launches: dict) -> None:
    result = text_of(block.get("content")) if not isinstance(block.get("content"), str) else block["content"]
    stopped = STOPPED_ID.search(result)
    if stopped and stopped.group(1) in audit.tasks:
        audit.tasks[stopped.group(1)].ended = "stopped"
    launch = launches.get(block.get("tool_use_id"))
    if not launch:
        return
    kind, description = launch
    for pattern in (BACKGROUND_ID, MONITOR_ID, AGENT_ID):
        found = pattern.search(result)
        if found:
            audit.tasks[found.group(1)] = BackgroundTask(found.group(1), kind, description, timestamp)
            return


def audit_transcript(path: str) -> Audit:
    audit = Audit()
    launches: dict = {}
    with open(path, encoding="utf-8") as transcript:
        for line in transcript:
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            timestamp = entry.get("timestamp", "")
            kind = entry.get("type")
            if kind == "attachment" and entry.get("attachment", {}).get("type") == "queued_command":
                record_message(audit, timestamp, text_of(entry["attachment"].get("prompt")), "sent mid-turn")
            if kind not in ("user", "assistant") or entry.get("isMeta"):
                continue
            content = entry.get("message", {}).get("content")
            if kind == "user" and isinstance(content, str):
                record_message(audit, timestamp, content, "prompt")
                continue
            for block in content if isinstance(content, list) else []:
                if block.get("type") == "tool_use":
                    record_tool_use(audit, block, launches)
                elif block.get("type") == "tool_result":
                    record_tool_result(audit, block, timestamp, launches)
                elif kind == "user" and block.get("type") == "text":
                    record_message(audit, timestamp, block.get("text", ""), "prompt")
    return audit


def spec_file_state(path: str) -> str:
    if not os.path.exists(path):
        return "missing on disk"
    with open(path, encoding="utf-8") as spec:
        text = spec.read()
    if os.path.basename(path) == "tasks.md":
        after_status = text.split("## Status", 1)[1].strip().splitlines() if "## Status" in text else []
        status = after_status[0] if after_status else "no ## Status heading"
        lines = [line.lstrip() for line in text.splitlines()]
        counts = ", ".join(
            f"{label} {sum(line.startswith(marker) for line in lines)}" for label, marker in TASK_MARKERS.items()
        )
        return f"status {status} | {counts}"
    if os.path.basename(path).startswith("code-review"):
        return "rows: " + ", ".join(f"{marker} {text.count(marker)}" for marker in REVIEW_MARKERS)
    return "exists"


def print_report(audit: Audit, path: str) -> None:
    print(f"# Session audit\n\nTranscript: {path}\n")
    print(f"## User requests ({len(audit.messages)})\n")
    for index, (timestamp, text, source) in enumerate(audit.messages, 1):
        preview = text if len(text) <= PREVIEW_CHARS else text[:PREVIEW_CHARS] + "…"
        print(f"M{index}. [{timestamp}] ({source}) {preview}")
    open_tasks = [task for task in audit.tasks.values() if not task.ended]
    print(f"\n## Background work ({len(audit.tasks)} started, {len(open_tasks)} with no end seen)\n")
    for task in audit.tasks.values():
        state = task.ended or "OPEN: no end notification or stop seen"
        print(f"- {task.task_id} | {task.kind} | {task.description} | started {task.launched_at} | {state}")
    spec_files = sorted(path for folder in audit.spec_dirs for path in glob.glob(os.path.join(folder, "*.md")))
    print(f"\n## agent-spec files in the folders this session touched ({len(spec_files)})\n")
    for spec_path in spec_files:
        print(f"- {spec_path} | {spec_file_state(spec_path)}")
    print(f"\nOPEN background work: {len(open_tasks)}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--session-id", help="Session id; the transcript is found under ~/.claude/projects.")
    group.add_argument("--transcript", help="Path to a session .jsonl transcript.")
    args = parser.parse_args()
    path = args.transcript or find_transcript(args.session_id)
    print_report(audit_transcript(path), path)


if __name__ == "__main__":
    main()
