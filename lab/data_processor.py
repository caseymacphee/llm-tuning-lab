"""Process session data for fine-tuning."""

import json
from pathlib import Path
from glob import glob
from typing import Iterator
from dataclasses import dataclass

from lab.constants import TOOL_PREAMBLE
from lab.loader import load_tool_catalogue


@dataclass
class TrainingExample:
    """A single training example with input and expected output."""
    input: str
    output: str
    metadata: dict


def load_session_files(data_dir: str, pattern: str = "*.jsonl") -> list[Path]:
    """Load all session files matching the pattern."""
    data_path = Path(data_dir)
    if not data_path.exists():
        raise FileNotFoundError(f"Data directory not found: {data_dir}")
    
    files = list(data_path.glob(pattern))
    if not files:
        raise ValueError(f"No files found matching pattern: {pattern} in {data_dir}")
    
    return sorted(files)


def inject_system_additions(system_prompt: str, inject_preamble: bool = True) -> str:
    """Inject tool preamble into system prompt."""
    if not inject_preamble:
        return system_prompt
    
    # Prepend preamble to the original system prompt
    return "\n\n".join([TOOL_PREAMBLE, system_prompt])


def process_session_turn(turn_data: dict, inject_preamble: bool = True, inject_catalog: bool = True) -> TrainingExample:
    """
    Process a single turn from a session file.
    
    Args:
        turn_data: Dict containing 'request' and 'response' keys
        inject_preamble: Whether to inject tool preamble into system prompt
        inject_catalog: Whether to populate tools key with tool catalog
    
    Returns:
        TrainingExample with formatted input and output
    """
    request = turn_data["request"]
    response = turn_data["response"]
    
    # Get system prompt and inject preamble if requested
    original_system = request.get("system", "")
    enhanced_system = inject_system_additions(original_system, inject_preamble)
    
    # Populate tools key with catalog if requested
    tools = request.get("tools")
    if inject_catalog and tools is None:
        # Load the tool catalogue and populate the tools key
        tools = load_tool_catalogue()
    
    # Format input: system + tools + conversation history
    messages = request.get("messages", [])
    
    # Build the input prompt
    input_parts = [f"<|system|>\n{enhanced_system}\n<|end|>"]
    
    # Add tools section if present
    if tools:
        tools_json = json.dumps(tools, indent=2)
        input_parts.append(f"<|tools|>\n{tools_json}\n<|end|>")
    
    for msg in messages:
        role = msg["role"]
        content = msg["content"]
        input_parts.append(f"<|{role}|>\n{content}\n<|end|>")
    
    input_text = "\n\n".join(input_parts)
    
    # Format output
    output_content = response.get("content", "")
    if isinstance(output_content, list):
        # Handle tool calls (array of tool use objects)
        output_text = json.dumps(output_content)
    else:
        output_text = output_content
    
    metadata = {
        "has_tools": tools is not None,
        "num_messages": len(messages),
        "response_type": "tool_calls" if isinstance(output_content, list) else "text"
    }
    
    return TrainingExample(
        input=input_text,
        output=output_text,
        metadata=metadata
    )


def load_training_data(
    data_dir: str,
    file_patterns: list[str],
    inject_preamble: bool = True,
    inject_catalog: bool = True
) -> Iterator[TrainingExample]:
    """
    Load and process training data from session files.
    
    Args:
        data_dir: Directory containing session files
        file_patterns: List of glob patterns for files to load
        inject_preamble: Whether to inject tool preamble
        inject_catalog: Whether to inject tool catalog
    
    Yields:
        TrainingExample objects
    """
    for pattern in file_patterns:
        files = load_session_files(data_dir, pattern)
        
        for file_path in files:
            with open(file_path, "r") as f:
                for line_num, line in enumerate(f, 1):
                    if not line.strip():
                        continue
                    
                    try:
                        turn_data = json.loads(line)
                        example = process_session_turn(turn_data, inject_preamble, inject_catalog)
                        yield example
                    except json.JSONDecodeError as e:
                        print(f"Warning: Skipping invalid JSON in {file_path}:{line_num}: {e}")
                    except KeyError as e:
                        print(f"Warning: Missing required key in {file_path}:{line_num}: {e}")


def preview_examples(examples: list[TrainingExample], num_examples: int = 3) -> None:
    """
    Print a preview of training examples for inspection.
    
    Args:
        examples: List of TrainingExample objects
        num_examples: Number of examples to preview
    """
    print(f"\n{'='*80}")
    print(f"PREVIEW OF {min(num_examples, len(examples))} TRAINING EXAMPLES")
    print(f"{'='*80}\n")
    
    for i, example in enumerate(examples[:num_examples], 1):
        print(f"\n{'-'*80}")
        print(f"EXAMPLE {i}")
        print(f"{'-'*80}")
        print(f"\nMETADATA: {example.metadata}")
        print(f"\n[INPUT] ({len(example.input)} chars)")
        print(f"{'-'*40}")
        print(example.input[:500] + ("..." if len(example.input) > 500 else ""))
        print(f"\n[OUTPUT] ({len(example.output)} chars)")
        print(f"{'-'*40}")
        print(example.output[:500] + ("..." if len(example.output) > 500 else ""))
    
    print(f"\n{'='*80}\n")

