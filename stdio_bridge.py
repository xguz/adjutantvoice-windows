"""stdio-to-HTTP bridge for the running AdjutantVoice MCP server.

Claude Desktop chat only launches stdio MCP servers. This forwards its tool calls to the
always-on server (http://127.0.0.1:<AV_MCP_PORT>/mcp), so chat shares that server's model
instead of loading a second copy. Lightweight: it never imports torch.
Run with the AdjutantVoice venv's python.exe (not pythonw: it needs stdin/stdout).
"""
import os

os.environ.setdefault("FASTMCP_SHOW_SERVER_BANNER", "false")

from adjutantvoice.config import settings  # noqa: E402
from fastmcp.server import create_proxy  # noqa: E402

if __name__ == "__main__":
    create_proxy(f"http://127.0.0.1:{settings.mcp_port}/mcp", name="AdjutantVoice").run()
