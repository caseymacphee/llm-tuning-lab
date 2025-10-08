"""Fine-tune LLM with LoRA using session data."""

import logging
import click
import torch
from datasets import Dataset
from transformers import AutoTokenizer, AutoModelForCausalLM, TrainingArguments
from peft import LoraConfig as PeftLoraConfig, get_peft_model, TaskType
from trl import SFTTrainer

from lab.config import load_config
from lab.data_processor import load_training_data

logger = logging.getLogger(__name__)


def prepare_datasets(config):
    """
    Prepare training and evaluation datasets from session data.
    
    Args:
        config: Configuration object
    
    Returns:
        Tuple of (train_dataset, eval_dataset)
    """
    # Load training examples
    train_examples = list(load_training_data(
        data_dir=config.data.data_dir,
        file_patterns=config.data.train_files or ["*session*.jsonl"],
        inject_preamble=config.data.inject_tool_preamble,
        inject_catalog=config.data.inject_tool_catalog
    ))
    
    # Split into train/eval if no separate eval files specified
    if not config.data.eval_files:
        # Use 10% for evaluation
        split_idx = int(len(train_examples) * 0.9)
        train_data = train_examples[:split_idx]
        eval_data = train_examples[split_idx:]
    else:
        train_data = train_examples
        eval_data = list(load_training_data(
            data_dir=config.data.data_dir,
            file_patterns=config.data.eval_files,
            inject_preamble=config.data.inject_tool_preamble,
            inject_catalog=config.data.inject_tool_catalog
        ))
    
    # Convert to HuggingFace datasets
    train_dataset = Dataset.from_dict({
        "input": [ex.input for ex in train_data],
        "output": [ex.output for ex in train_data]
    })
    
    eval_dataset = Dataset.from_dict({
        "input": [ex.input for ex in eval_data],
        "output": [ex.output for ex in eval_data]
    })
    
    return train_dataset, eval_dataset


def setup_model_and_tokenizer(config):
    """
    Load and prepare model and tokenizer.
    
    Args:
        config: Configuration object
    
    Returns:
        Tuple of (model, tokenizer)
    """
    # Load tokenizer
    tokenizer = AutoTokenizer.from_pretrained(config.model.base_model, use_fast=True)
    tokenizer.pad_token = tokenizer.eos_token
    
    # Load model
    dtype = getattr(torch, config.model.torch_dtype)
    model = AutoModelForCausalLM.from_pretrained(
        config.model.base_model,
        torch_dtype=dtype,
        device_map=config.model.device_map
    )
    
    # Apply LoRA
    lora_config = PeftLoraConfig(
        task_type=TaskType.CAUSAL_LM,
        r=config.lora.r,
        lora_alpha=config.lora.lora_alpha,
        lora_dropout=config.lora.lora_dropout,
        target_modules=config.lora.target_modules
    )
    model = get_peft_model(model, lora_config)
    
    # Print trainable parameters
    model.print_trainable_parameters()
    
    return model, tokenizer


def create_training_arguments(config):
    """
    Create TrainingArguments from config.
    
    Args:
        config: Configuration object
    
    Returns:
        TrainingArguments object
    """
    return TrainingArguments(
        output_dir=config.training.output_dir,
        num_train_epochs=config.training.num_train_epochs,
        per_device_train_batch_size=config.training.per_device_train_batch_size,
        per_device_eval_batch_size=config.training.per_device_eval_batch_size,
        gradient_accumulation_steps=config.training.gradient_accumulation_steps,
        learning_rate=config.training.learning_rate,
        bf16=config.training.bf16,
        logging_steps=config.training.logging_steps,
        evaluation_strategy=config.training.evaluation_strategy,
        eval_steps=config.training.eval_steps,
        save_steps=config.training.save_steps,
        lr_scheduler_type=config.training.lr_scheduler_type,
        warmup_ratio=config.training.warmup_ratio,
        report_to=config.training.report_to
    )


@click.command()
@click.option('--log-level', type=click.Choice(['DEBUG', 'INFO', 'WARNING', 'ERROR']), default='INFO', help='Logging level')
def train(log_level):
    """
    Main training function.
    
    Configure training via environment variables (LLM_*) or config file.
    See README for configuration options.
    """
    # Setup logging
    logging.basicConfig(
        level=getattr(logging, log_level),
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    # Load config from environment or defaults
    config = load_config()
    
    logger.info(
        "Starting training with config: "
        "base_model=%s, output_dir=%s, lora_r=%d, lora_alpha=%d, "
        "learning_rate=%f, batch_size=%d, epochs=%d, bf16=%s",
        config.model.base_model,
        config.training.output_dir,
        config.lora.r,
        config.lora.lora_alpha,
        config.training.learning_rate,
        config.training.per_device_train_batch_size,
        config.training.num_train_epochs,
        config.training.bf16
    )
    
    # Prepare data
    logger.info("Loading and preparing datasets from data_dir=%s", config.data.data_dir)
    train_dataset, eval_dataset = prepare_datasets(config)
    logger.info(
        "Datasets prepared: train_examples=%d, eval_examples=%d",
        len(train_dataset),
        len(eval_dataset)
    )
    
    # Setup model and tokenizer
    logger.info("Loading model=%s with device_map=%s", config.model.base_model, config.model.device_map)
    model, tokenizer = setup_model_and_tokenizer(config)
    
    # Create training arguments
    training_args = create_training_arguments(config)
    
    # Create trainer
    logger.info(
        "Initializing SFTTrainer with max_seq_length=%d, gradient_accumulation_steps=%d",
        config.data.max_length,
        config.training.gradient_accumulation_steps
    )
    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=train_dataset,
        eval_dataset=eval_dataset,
        args=training_args,
        max_seq_length=config.data.max_length
    )
    
    # Train
    logger.info("Beginning training loop for %d epochs", config.training.num_train_epochs)
    trainer.train()
    
    # Save
    logger.info("Training complete, saving model to output_dir=%s", config.training.output_dir)
    trainer.save_model(config.training.output_dir)
    tokenizer.save_pretrained(config.training.output_dir)
    logger.info("Model and tokenizer saved successfully")


if __name__ == "__main__":
    train()