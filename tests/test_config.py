"""Tests for configuration."""

import pytest
from lab.config import (
    LoRAConfig,
    TrainingConfig,
    DataConfig,
    ModelConfig,
    Config,
    load_config
)


def test_lora_config_defaults():
    """Test LoRA configuration defaults."""
    config = LoRAConfig()
    assert config.r == 16
    assert config.lora_alpha == 32
    assert config.lora_dropout == 0.05
    assert "q_proj" in config.target_modules


def test_training_config_defaults():
    """Test training configuration defaults."""
    config = TrainingConfig()
    assert config.num_train_epochs == 2
    assert config.learning_rate == 2e-4
    assert config.bf16 is True
    assert config.lr_scheduler_type == "cosine"


def test_data_config_defaults():
    """Test data configuration defaults."""
    config = DataConfig()
    assert config.data_dir == "data"
    assert config.max_length == 4096
    assert config.inject_tool_preamble is True
    assert config.inject_tool_catalog is True


def test_model_config_defaults():
    """Test model configuration defaults."""
    config = ModelConfig()
    assert "llama" in config.base_model.lower()
    assert config.torch_dtype == "bfloat16"
    assert config.device_map == "auto"


def test_full_config():
    """Test complete configuration."""
    config = Config()
    assert isinstance(config.model, ModelConfig)
    assert isinstance(config.data, DataConfig)
    assert isinstance(config.lora, LoRAConfig)
    assert isinstance(config.training, TrainingConfig)


def test_load_config():
    """Test config loading function."""
    config = load_config()
    assert isinstance(config, Config)

