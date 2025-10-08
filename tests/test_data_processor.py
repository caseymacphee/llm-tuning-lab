"""Tests for data processing functionality."""

import json
import pytest
from pathlib import Path
from lab.data_processor import (
    inject_system_additions,
    process_session_turn,
    TrainingExample
)


def test_inject_system_additions():
    """Test system prompt injection with preamble."""
    original = "You are a helpful assistant."
    
    # With preamble
    enhanced = inject_system_additions(original, inject_preamble=True)
    assert "TOOL_PREAMBLE" in enhanced
    assert original in enhanced
    
    # Without preamble
    enhanced = inject_system_additions(original, inject_preamble=False)
    assert enhanced == original


def test_process_session_turn():
    """Test processing a single session turn."""
    turn_data = {
        "request": {
            "system": "You are a test assistant.",
            "tools": None,
            "messages": [
                {"role": "user", "content": "Hello!"}
            ]
        },
        "response": {
            "role": "assistant",
            "content": "Hi there!"
        }
    }
    
    # Without injecting anything
    example = process_session_turn(turn_data, inject_preamble=False, inject_catalog=False)
    
    assert isinstance(example, TrainingExample)
    assert "You are a test assistant" in example.input
    assert "Hello!" in example.input
    assert example.output == "Hi there!"
    assert example.metadata["response_type"] == "text"
    assert not example.metadata["has_tools"]
    
    # With catalog injection
    example = process_session_turn(turn_data, inject_preamble=False, inject_catalog=True)
    assert example.metadata["has_tools"]
    assert "<|tools|>" in example.input
    assert "github_find_repositories" in example.input  # Should have actual tools from catalog


def test_process_session_turn_with_tool_calls():
    """Test processing a turn with tool calls."""
    turn_data = {
        "request": {
            "system": "You are a test assistant.",
            "tools": None,
            "messages": [
                {"role": "user", "content": "Search for something"}
            ]
        },
        "response": {
            "role": "assistant",
            "content": [
                {
                    "type": "tool_use",
                    "id": "call_123",
                    "name": "search",
                    "input": {"query": "test"}
                }
            ]
        }
    }
    
    example = process_session_turn(turn_data, inject_preamble=False, inject_catalog=False)
    
    assert isinstance(example, TrainingExample)
    assert example.metadata["response_type"] == "tool_calls"
    # Output should be JSON string
    output_data = json.loads(example.output)
    assert isinstance(output_data, list)
    assert output_data[0]["name"] == "search"


def test_training_example_metadata():
    """Test that metadata is properly populated."""
    turn_data = {
        "request": {
            "system": "System prompt",
            "tools": {"some": "tools"},
            "messages": [
                {"role": "user", "content": "Message 1"},
                {"role": "assistant", "content": "Response 1"},
                {"role": "user", "content": "Message 2"}
            ]
        },
        "response": {
            "role": "assistant",
            "content": "Final response"
        }
    }
    
    example = process_session_turn(turn_data, inject_preamble=False, inject_catalog=False)
    
    assert example.metadata["has_tools"] is True
    assert example.metadata["num_messages"] == 3
    assert example.metadata["response_type"] == "text"


def test_complete_tool_catalog_and_preamble_injection():
    """Test complete tool catalog and preamble injection."""
    turn_data = {
        "request": {
            "system": "You are a helpful assistant.",
            "tools": None,  # This should trigger catalog injection
            "messages": [
                {"role": "user", "content": "Find a GitHub repo"}
            ]
        },
        "response": {
            "role": "assistant",
            "content": [
                {
                    "type": "tool_use",
                    "id": "toolu_123",
                    "name": "github_find_repositories",
                    "input": {"query": "test"}
                }
            ]
        }
    }
    
    # Test with both preamble and catalog injection
    example = process_session_turn(turn_data, inject_preamble=True, inject_catalog=True)
    
    # Verify preamble is injected
    assert "<TOOL_PREAMBLE>" in example.input
    assert "You can optionally call tools" in example.input
    assert 'type":"tool_use"' in example.input or "tool_use" in example.input
    
    # Verify tool catalog section exists
    assert "<|tools|>" in example.input
    
    # Verify actual tool definitions are present
    assert "github_find_repositories" in example.input
    assert "jira_get_issue" in example.input
    assert "web_fetch" in example.input
    
    # Verify tools are in JSON format
    tools_start = example.input.find("<|tools|>")
    tools_end = example.input.find("<|user|>", tools_start)
    tools_section = example.input[tools_start:tools_end]
    
    # Should contain JSON-formatted tool definitions
    assert '"name"' in tools_section
    assert '"description"' in tools_section
    assert '"input_schema"' in tools_section
    
    # Verify original system prompt is still there
    assert "You are a helpful assistant" in example.input
    
    # Verify metadata
    assert example.metadata["has_tools"] is True
    assert example.metadata["response_type"] == "tool_calls"
    
    # Verify output is JSON formatted tool calls
    output_data = json.loads(example.output)
    assert isinstance(output_data, list)
    assert output_data[0]["type"] == "tool_use"
    assert output_data[0]["name"] == "github_find_repositories"


def test_preamble_only_no_catalog():
    """Test injecting preamble without tool catalog."""
    turn_data = {
        "request": {
            "system": "Original system prompt",
            "tools": None,
            "messages": [{"role": "user", "content": "Hello"}]
        },
        "response": {
            "role": "assistant",
            "content": "Hi!"
        }
    }
    
    # Only preamble, no catalog
    example = process_session_turn(turn_data, inject_preamble=True, inject_catalog=False)
    
    # Should have preamble
    assert "<TOOL_PREAMBLE>" in example.input
    
    # Should NOT have tools section since catalog injection is False
    assert "<|tools|>" not in example.input
    
    # Original system should be present
    assert "Original system prompt" in example.input

