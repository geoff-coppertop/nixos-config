{
  lib,
  python3Packages,
  fetchPypi,
}:
python3Packages.buildPythonApplication {
  pname = "mcp-obsidian";
  version = "0.2.2";
  pyproject = true;

  src = fetchPypi {
    pname = "mcp_obsidian";
    version = "0.2.2";
    hash = "sha256-Gg6CQAVvzDsQ6Qq3Yme8KacZEEjLqq6565QaphfsPNo=";
  };

  build-system = [python3Packages.hatchling];

  dependencies = with python3Packages; [
    mcp
    requests
    python-dotenv
  ];

  meta = {
    description = "MCP server for Obsidian via the Local REST API plugin";
    homepage = "https://github.com/MarkusPfundstein/mcp-obsidian";
    license = lib.licenses.mit;
    mainProgram = "mcp-obsidian";
  };
}
