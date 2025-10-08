#!/usr/bin/env python3
"""Check mode script to preview training data before fine-tuning."""

import argparse
from lab.config import load_config
from lab.data_processor import load_training_data, preview_examples


def main():
    parser = argparser = argparse.ArgumentParser(
        description="Preview training data with injected preamble and catalog"
    )
    parser.add_argument(
        "--data-dir",
        type=str,
        default="data",
        help="Directory containing session files"
    )
    parser.add_argument(
        "--pattern",
        type=str,
        default="*.jsonl",
        help="Glob pattern for session files"
    )
    parser.add_argument(
        "--num-examples",
        type=int,
        default=3,
        help="Number of examples to preview"
    )
    parser.add_argument(
        "--no-preamble",
        action="store_true",
        help="Disable tool preamble injection"
    )
    parser.add_argument(
        "--no-catalog",
        action="store_true",
        help="Disable tool catalog injection"
    )
    parser.add_argument(
        "--stats",
        action="store_true",
        help="Show statistics about the dataset"
    )
    
    args = parser.parse_args()
    
    # Load configuration
    config = load_config()
    
    # Override with command-line args
    data_dir = args.data_dir or config.data.data_dir
    inject_preamble = not args.no_preamble and config.data.inject_tool_preamble
    inject_catalog = not args.no_catalog and config.data.inject_tool_catalog
    
    print(f"\nLoading data from: {data_dir}")
    print(f"Pattern: {args.pattern}")
    print(f"Inject preamble: {inject_preamble}")
    print(f"Inject catalog: {inject_catalog}\n")
    
    # Load examples
    examples = list(load_training_data(
        data_dir=data_dir,
        file_patterns=[args.pattern],
        inject_preamble=inject_preamble,
        inject_catalog=inject_catalog
    ))
    
    print(f"Loaded {len(examples)} training examples")
    
    if args.stats:
        show_statistics(examples)
    
    # Preview examples
    preview_examples(examples, num_examples=args.num_examples)


def show_statistics(examples):
    """Show statistics about the dataset."""
    print(f"\n{'='*80}")
    print("DATASET STATISTICS")
    print(f"{'='*80}\n")
    
    total_examples = len(examples)
    total_input_chars = sum(len(ex.input) for ex in examples)
    total_output_chars = sum(len(ex.output) for ex in examples)
    
    has_tools_count = sum(1 for ex in examples if ex.metadata.get("has_tools"))
    text_responses = sum(1 for ex in examples if ex.metadata.get("response_type") == "text")
    tool_responses = sum(1 for ex in examples if ex.metadata.get("response_type") == "tool_calls")
    
    avg_input_chars = total_input_chars / total_examples if total_examples > 0 else 0
    avg_output_chars = total_output_chars / total_examples if total_examples > 0 else 0
    
    print(f"Total examples: {total_examples}")
    print(f"Average input length: {avg_input_chars:.0f} chars")
    print(f"Average output length: {avg_output_chars:.0f} chars")
    print(f"\nResponse types:")
    print(f"  - Text responses: {text_responses} ({text_responses/total_examples*100:.1f}%)")
    print(f"  - Tool call responses: {tool_responses} ({tool_responses/total_examples*100:.1f}%)")
    print(f"  - Examples with tools available: {has_tools_count} ({has_tools_count/total_examples*100:.1f}%)")
    print()


if __name__ == "__main__":
    main()

