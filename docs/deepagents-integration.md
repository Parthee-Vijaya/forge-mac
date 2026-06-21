# Drive Stormbreaker from a deepagents / LangGraph platform

Stormbreaker stays a native Swift app — and plugs into a Python agent platform as a
**specialized sub-agent** over MCP. Your `deepagents` "deep agent" (the hub) hands
off "build me this app" and Stormbreaker's own self-correcting loop does it natively
underneath. No rewrite; one control plane.

## The bridge: `storm-mcp`

`storm-mcp` is a stdio MCP server exposing a Stormbreaker project as tools:

| Tool | What |
|------|------|
| `list_files` / `read_file` / `write_file` | explore + edit project files (jailed to the project) |
| `run_command` | run a shell command in the project root (`npm install`, …) |
| `get_errors` | type-check (`tsc --noEmit`) → deduped, classified errors |
| **`build`** | **delegate a whole build to Stormbreaker's agent** — scaffold + write + install + self-correct, returns a summary (files changed, clean/errors, preview URL) |

`build` is the sub-agent handoff; the rest let the hub do fine-grained work in the
same project.

## Wire it into deepagents (Python)

```python
import asyncio
from deepagents import create_deep_agent
from langchain_mcp_adapters.client import MultiServerMCPClient

async def main():
    # storm-mcp on PATH (curl install) or an absolute path to the binary.
    client = MultiServerMCPClient({
        "storm": {
            "command": "storm-mcp",
            "args": ["/abs/path/to/your/project"],   # the project root storm-mcp manages
            "transport": "stdio",
            "env": {"STORM_CLOUD_API_KEY": "…"},      # only if you use a cloud model
        }
    })
    tools = await client.get_tools()
    # deepagents ships its own read_file/write_file (a virtual filesystem), so drop
    # storm's same-named tools to avoid a name collision (see Gotcha below).
    tools = [t for t in tools if t.name not in {"read_file", "write_file"}]

    agent = create_deep_agent(
        tools=tools,
        system_prompt=(
            "You orchestrate specialists. To build or change a web app, call the "
            "`build` tool — it delegates to Stormbreaker's own coding agent. Use "
            "`get_errors` to inspect the result."
        ),
    )

    result = await agent.ainvoke({"messages": [
        {"role": "user", "content": "Build a counter app with + / − / reset, modern style."}
    ]})
    print(result["messages"][-1].content)

asyncio.run(main())
```

The deep agent now plans, calls `build` (Stormbreaker writes a real Vite/React project
and fixes its own type errors), then can `get_errors` to verify — all while
Stormbreaker stays a fast native binary. The model used by `build` comes from
`~/.config/storm/config.json` (or the `model` / `provider` build args).

### Gotcha: tool-name collisions

deepagents has **built-in** `read_file` / `write_file` (its virtual filesystem), which
clash with storm's same-named tools — `create_deep_agent` raises `TOOL_NAME_COLLISION`.
Two fixes: **drop** storm's colliding tools (above — the hub uses its own fs + storm's
unique `build` / `get_errors` / `run_command` / `list_files`), or **prefix** the MCP
tools so they become `storm__build`, `storm__read_file`, … (JS adapter:
`prefixToolNameWithServerName: true`; Python: the equivalent option for your adapter
version).

### Verified TS example

A runnable TS demo (deepagents.js + `@langchain/mcp-adapters`) lives in the
`research-agent` project: `scripts/storm-hub-demo.ts`. It loads all six storm tools
(prefixed `storm__…`) and delegates a build. Note: the **hub** model must support
tool-calling — some local LM Studio chat templates can't render tool-call messages
(null content) and 400; a cloud model or a properly-templated local model works.

> `build` is long-running (scaffold + `npm install` + model turns). Give the tool a
> generous timeout in your client. The dev server is started for HMR/runtime checks
> and shut down when the build returns.

## Why this and not "rewrite Stormbreaker in Python"

One platform = one **orchestration layer**, not one language. deepagents is the hub;
Stormbreaker, your research-agent, and the rest stay best-in-class in their own stacks
and talk over MCP. You keep Stormbreaker's native launch, single binary, local-first
privacy and security hardening — and still get the unified control plane.
