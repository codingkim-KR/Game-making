"""Minimal stdio client for aseprite-mcp, so its tools can be called from the shell.

Usage:
  python asep.py list                      # list tool names
  python asep.py call <tool> '<json args>' # call one tool, print text result
"""
import asyncio
import json
import os
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

REPO = os.path.expanduser("~/tools/aseprite-mcp")
ASEPRITE = os.path.expanduser("~/tools/aseprite/build/bin/aseprite")


async def main(argv):
    params = StdioServerParameters(
        command="uv",
        args=["--directory", REPO, "run", "-m", "aseprite_mcp"],
        env={**os.environ, "ASEPRITE_PATH": ASEPRITE},
    )
    async with stdio_client(params) as (r, w):
        async with ClientSession(r, w) as s:
            await s.initialize()
            if argv[0] == "list":
                tools = (await s.list_tools()).tools
                for t in tools:
                    print(t.name)
                print(f"-- {len(tools)} tools")
            elif argv[0] == "call":
                args = json.loads(argv[2]) if len(argv) > 2 else {}
                res = await s.call_tool(argv[1], args)
                for c in res.content:
                    print(getattr(c, "text", f"<{c.type}>"))
                if res.isError:
                    sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1:]))
