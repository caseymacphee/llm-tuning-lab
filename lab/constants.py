"""
Constants for fine-tuning data preparation.

The tool preamble provides instructions on HOW to use tools.
The tool catalog (loaded from tool_catalogue.json) defines WHAT tools are available.

During data processing:
- TOOL_PREAMBLE is injected into the system prompt
- Tool catalog is injected into the 'tools' key as structured JSON
"""

TOOL_PREAMBLE = """
<TOOL_PREAMBLE>
You can optionally call tools. Available tools are provided in the tools section.

FORMAT
- To call a tool, output exactly one JSON object per tool call:
  {"type":"tool_use","id":"toolu_<unique_id>","name":"<tool_name>","input":{<parameters>}}
- The "id" field must be unique for each tool call (e.g., "toolu_01AbCdEfGhIjKlMnOp")
- The "input" field contains the tool parameters as a JSON object
- If no tool is needed, write a normal assistant reply (no JSON).
- You can make multiple tool calls in one response by outputting an array of tool_use objects
- After a tool_result is shown in the conversation, ground your reply in that result. If another call is needed, emit new tool_use objects.

RULES
- Use only tools available in the provided tools catalog.
- Parameters in "input" must be valid JSON and match the tool's input_schema exactly (no extra keys).
- Required parameters must always be provided; optional parameters can be omitted.
- Parameters account_id, user_id, and session_id are auto-injected by the system - do not include them in your tool calls.
- If the needed tool is missing, say so and propose a manual workaround.
- Never fabricate tool results; only reason over provided tool_result blocks.
- Prefer making all needed tool calls at once when possible; if multi-step reasoning is required, do it turn-by-turn.

VALIDATION
- If you receive a validator error (type=tool_error, name=_validator), correct the call and emit a new tool_use object.

OUTPUT
- Do not wrap the JSON in code fences or add commentary on the same line.
- Choose a tool only when it adds essential info or executes an action.
</TOOL_PREAMBLE>
"""