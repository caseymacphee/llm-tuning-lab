# LLM Tuning Lab

Fine-tuning infrastructure for LLMs with LoRA, designed to process agent session data and inject tool preambles/catalogs.

## Project Structure

```
llm-tuning-lab/
├── lab/                          # Main package
│   ├── __init__.py
│   ├── config.py                 # Pydantic settings for training config
│   ├── constants.py              # Tool preamble templates
│   ├── loader.py                 # Tool catalog loading/generation
│   ├── data_processor.py         # Session data processing
│   ├── train_lora.py             # Main training script
│   └── check_data.py             # Data preview/check mode
├── data/                         # Training data (*.jsonl files)
│   └── tool_catalogue.json       # Tool definitions
├── tests/                        # Pytest tests
│   ├── test_config.py
│   └── test_data_processor.py
├── Pipfile                       # Pipenv dependencies
├── Dockerfile                    # Docker configuration
├── docker-compose.yml            # Docker Compose setup
├── pyproject.toml                # Package metadata
└── pytest.ini                    # Pytest configuration
```

## Features

### ✅ Configuration Management
- Pydantic-based configuration with environment variable support
- Separate configs for Model, Data, LoRA, and Training parameters
- Environment variables prefixed with `LLM_` (e.g., `LLM_MODEL__BASE_MODEL`)

### ✅ Data Processing
- Loads agent session data from JSONL files
- Injects tool preamble and dynamic tool catalog into system prompts
- Handles both text responses and tool call responses
- Automatic train/eval splitting

### ✅ Check Mode
- Preview formatted training data before running expensive training
- See exact input/output that will be used for fine-tuning
- Statistics about dataset composition

### ✅ Testing Infrastructure
- Pytest configured with coverage reporting
- Tests for configuration and data processing
- Run with: `docker exec llm-tuning-dev pipenv run pytest` or `pipenv run pytest`

## Installation

**Recommended**: Use Docker for a consistent environment without local Python build issues.

### Option 1: Using Docker (Recommended)

```bash
# Build and start the container
docker-compose build
docker-compose up -d

# Install dependencies (first time only, or after Pipfile changes)
docker exec llm-tuning-dev pipenv install --dev
docker exec llm-tuning-dev pipenv run pip install -e .

# Run commands inside the container
docker exec llm-tuning-dev pipenv run python lab/check_data.py --num-examples=3
docker exec llm-tuning-dev pipenv run python lab/train_lora.py --help

# Or get a shell inside the container
docker exec -it llm-tuning-dev bash
```

### Option 2: Local Installation (with pipenv)

**Note**: Requires Python 3.12 with lzma support. Local setup can be tricky due to Python build dependencies.

```bash
# Install pipenv
pip install pipenv

# Install dependencies
pipenv install --dev
pipenv run pip install -e .

# Run commands
pipenv run python lab/check_data.py --num-examples=3
pipenv run python lab/train_lora.py --help
```

## Usage

### 1. Check Mode - Preview Training Data

Before running training, preview your data to ensure it's formatted correctly:

```bash
# Using Docker (recommended)
docker exec llm-tuning-dev pipenv run python lab/check_data.py --num-examples=3 --stats

# Or with local pipenv
pipenv run python lab/check_data.py --num-examples=3 --stats

# Preview from specific pattern  
docker exec llm-tuning-dev pipenv run python lab/check_data.py --pattern="agent-session-*.jsonl" --num-examples=5

# Disable tool catalog injection (for testing)
docker exec llm-tuning-dev pipenv run python lab/check_data.py --no-catalog
```

This will show:
- Dataset statistics (total examples, avg lengths, response types)
- Sample formatted inputs with injected preambles/catalogs
- Expected outputs
- Metadata about each example

### 2. Configure Training

Set environment variables to customize training:

```bash
# Model configuration
export LLM_MODEL__BASE_MODEL="meta-llama/Meta-Llama-3-8B-Instruct"
export LLM_MODEL__TORCH_DTYPE="bfloat16"

# Data configuration
export LLM_DATA__DATA_DIR="data"
export LLM_DATA__MAX_LENGTH="4096"

# LoRA configuration
export LLM_LORA__R="16"
export LLM_LORA__LORA_ALPHA="32"

# Training configuration
export LLM_TRAINING__NUM_TRAIN_EPOCHS="2"
export LLM_TRAINING__LEARNING_RATE="2e-4"
export LLM_TRAINING__OUTPUT_DIR="out/lora-ckpt"
```

Or create a `.env` file and source it.

### 3. Run Training

```bash
# Using Docker (recommended)
docker exec llm-tuning-dev pipenv run python lab/train_lora.py

# Or with local pipenv
pipenv run python lab/train_lora.py

# Optional: Set log level
docker exec llm-tuning-dev pipenv run python lab/train_lora.py --log-level DEBUG
```

The training script will:
1. Load configuration from environment variables or defaults
2. Process session data files with injected tool preambles/catalogs
3. Split into train/eval sets
4. Setup model with LoRA adapters
5. Train and save checkpoints

**Configuration**: All settings are managed via environment variables (prefixed with `LLM_`) or use defaults from `lab/config.py`. See section 2 above for examples.

## Data Format

Your session data should be in JSONL format with each line containing:

```json
{
  "request": {
    "system": "Original system prompt...",
    "tools": null,
    "messages": [
      {"role": "user", "content": "User message"},
      {"role": "assistant", "content": "Assistant response"}
    ]
  },
  "response": {
    "role": "assistant",
    "content": "Expected response or tool calls"
  }
}
```

## Configuration Reference

### Model Config
- `base_model`: HuggingFace model identifier
- `torch_dtype`: PyTorch dtype (bfloat16, float16, float32)
- `device_map`: Device mapping strategy (auto, cuda, cpu)

### Data Config
- `data_dir`: Directory containing training data
- `train_files`: List of glob patterns for training files
- `eval_files`: List of glob patterns for eval files (optional)
- `max_length`: Maximum sequence length
- `inject_tool_preamble`: Whether to inject tool usage instructions
- `inject_tool_catalog`: Whether to inject tool catalog

### LoRA Config
- `r`: LoRA rank (lower = fewer parameters)
- `lora_alpha`: LoRA alpha parameter
- `lora_dropout`: Dropout rate
- `target_modules`: Which model layers to apply LoRA to

### Training Config
- `output_dir`: Where to save checkpoints
- `num_train_epochs`: Number of training epochs
- `per_device_train_batch_size`: Batch size per GPU
- `gradient_accumulation_steps`: Steps to accumulate gradients
- `learning_rate`: Learning rate
- `bf16`: Use bfloat16 precision
- `eval_steps`: Evaluate every N steps
- `save_steps`: Save checkpoint every N steps

## Testing

```bash
# Run all tests
poetry run pytest

# Run with coverage
poetry run pytest --cov=lab --cov-report=html

# Run specific test file
poetry run pytest tests/test_data_processor.py -v
```

## Tool Catalog

The tool catalog is dynamically generated from `tool_catalogue.json` and injected into the system prompt during training. This ensures the model learns the tool signatures and usage patterns.

To update the catalog:
1. Modify `lab/tool_catalogue.json`
2. The catalog format is automatically generated by `lab/loader.py`
3. Test with check mode to see the formatted output

## Troubleshooting

### Python Version Issues
If you see "Could not parse version constraint", you're likely on Python 3.13. Switch to 3.12:

```bash
pyenv install 3.12.11
pyenv virtualenv 3.12.11 llm-lab
pyenv activate llm-lab
```

### Out of Memory
- Reduce `per_device_train_batch_size`
- Increase `gradient_accumulation_steps` to maintain effective batch size
- Reduce `max_length`
- Use smaller model or lower LoRA rank

### Data Processing Errors
- Use check mode to preview data: `python lab/check_data.py`
- Check JSONL files are properly formatted
- Verify all required keys are present in session data

## License

MIT License - see LICENSE file
