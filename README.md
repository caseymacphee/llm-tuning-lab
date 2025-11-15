# LLM Tuning Lab

LoRA fine-tuning setup for LLMs. Takes agent session data and injects tool catalogs into the training data.

## Structure

```
lab/                    # training code
  ├── config.py         # pydantic config
  ├── data_processor.py # session data → training examples
  ├── train_lora.py     # main training script
  └── check_data.py     # preview data before training
infra/                  # terraform for AWS GPU instances
data/                   # your training data (gitignored)
```

## Quick Start

Using Docker (recommended):

```bash
docker-compose up -d
docker exec llm-tuning-dev pipenv install --dev
docker exec llm-tuning-dev pipenv run pip install -e .

# Preview your data
docker exec llm-tuning-dev pipenv run python lab/check_data.py --num-examples=3

# Train
docker exec llm-tuning-dev pipenv run python lab/train_lora.py
```

Or locally with pipenv (Python 3.12):

```bash
pipenv install --dev
pipenv run pip install -e .
pipenv run python lab/check_data.py --num-examples=3
pipenv run python lab/train_lora.py
```

## Configuration

Use environment variables with `LLM_` prefix:

```bash
export LLM_MODEL__BASE_MODEL="meta-llama/Meta-Llama-3-8B-Instruct"
export LLM_DATA__MAX_LENGTH="4096"
export LLM_LORA__R="16"
export LLM_TRAINING__NUM_TRAIN_EPOCHS="2"
export LLM_TRAINING__LEARNING_RATE="2e-4"
```

Or edit defaults in `lab/config.py`.

## Data Format

JSONL files with session data:

```json
{
  "request": {
    "system": "system prompt",
    "messages": [{"role": "user", "content": "..."}]
  },
  "response": {
    "role": "assistant",
    "content": "expected output"
  }
}
```

The tool catalog from `data/tool_catalogue.json` gets injected into system prompts automatically.

## Infrastructure

See `infra/` for Terraform setup to run training on AWS GPU instances (g5.xlarge spot instances for ~$0.30/hr).

```bash
cd infra/envs/training
terraform apply -var="create_instance=true"
```

More details in `infra/README.md` and `DEPLOYMENT.md`.

## Testing

```bash
pipenv run pytest
pipenv run pytest --cov=lab
```
