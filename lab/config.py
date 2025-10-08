"""Configuration for LLM fine-tuning using Pydantic settings."""

from pydantic_settings import BaseSettings
from pydantic import Field


class LoRAConfig(BaseSettings):
    """LoRA (Low-Rank Adaptation) configuration."""
    
    r: int = Field(default=16, description="LoRA rank")
    lora_alpha: int = Field(default=32, description="LoRA alpha parameter")
    lora_dropout: float = Field(default=0.05, description="LoRA dropout rate")
    target_modules: list[str] = Field(
        default=[
            "q_proj", "k_proj", "v_proj", "o_proj",
            "gate_proj", "up_proj", "down_proj"
        ],
        description="Target modules for LoRA adaptation"
    )


class TrainingConfig(BaseSettings):
    """Training hyperparameters and settings."""
    
    output_dir: str = Field(default="out/lora-ckpt", description="Output directory for checkpoints")
    num_train_epochs: int = Field(default=2, description="Number of training epochs")
    per_device_train_batch_size: int = Field(default=2, description="Training batch size per device")
    per_device_eval_batch_size: int = Field(default=2, description="Evaluation batch size per device")
    gradient_accumulation_steps: int = Field(default=8, description="Gradient accumulation steps")
    learning_rate: float = Field(default=2e-4, description="Learning rate")
    bf16: bool = Field(default=True, description="Use bfloat16 precision")
    logging_steps: int = Field(default=20, description="Log every N steps")
    evaluation_strategy: str = Field(default="steps", description="Evaluation strategy")
    eval_steps: int = Field(default=200, description="Evaluate every N steps")
    save_steps: int = Field(default=200, description="Save checkpoint every N steps")
    lr_scheduler_type: str = Field(default="cosine", description="Learning rate scheduler type")
    warmup_ratio: float = Field(default=0.05, description="Warmup ratio")
    report_to: str = Field(default="none", description="Reporting integration")


class DataConfig(BaseSettings):
    """Data processing configuration."""
    
    data_dir: str = Field(default="data", description="Directory containing training data")
    train_files: list[str] = Field(default=[], description="Training data files (glob patterns supported)")
    eval_files: list[str] = Field(default=[], description="Evaluation data files (glob patterns supported)")
    max_length: int = Field(default=4096, description="Maximum sequence length")
    inject_tool_preamble: bool = Field(default=True, description="Inject tool preamble into system prompts")
    inject_tool_catalog: bool = Field(default=True, description="Inject tool catalog into system prompts")


class ModelConfig(BaseSettings):
    """Model configuration."""
    
    base_model: str = Field(
        default="meta-llama/Meta-Llama-3-8B-Instruct",
        description="Base model identifier from HuggingFace"
    )
    torch_dtype: str = Field(default="bfloat16", description="PyTorch dtype for model")
    device_map: str = Field(default="auto", description="Device mapping strategy")


class Config(BaseSettings):
    """Complete configuration for fine-tuning."""
    
    model: ModelConfig = Field(default_factory=ModelConfig)
    data: DataConfig = Field(default_factory=DataConfig)
    lora: LoRAConfig = Field(default_factory=LoRAConfig)
    training: TrainingConfig = Field(default_factory=TrainingConfig)
    
    class Config:
        env_prefix = "LLM_"
        env_nested_delimiter = "__"


def load_config() -> Config:
    """Load configuration from environment variables or defaults."""
    return Config()

