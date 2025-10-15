#!/usr/bin/env python3
"""
Quick validation script to check API compatibility before deployment.
Run this in the Docker container to verify all APIs match expected signatures.
"""
import sys
import inspect
from typing import Set


def check_api_params(class_or_func, expected_params: Set[str], name: str) -> bool:
    """Check if a class/function has expected parameters."""
    sig = inspect.signature(class_or_func)
    actual_params = set(sig.parameters.keys())
    
    print(f"\n{name}:")
    print(f"  Expected params: {sorted(expected_params)}")
    print(f"  Actual params: {sorted(actual_params)}")
    
    missing = expected_params - actual_params
    if missing:
        print(f"  ❌ MISSING: {sorted(missing)}")
        return False
    
    print(f"  ✅ All expected params present")
    return True


def main():
    """Run all API validations."""
    print("=" * 70)
    print("API Compatibility Validation")
    print("=" * 70)
    
    all_valid = True
    
    # Check transformers version
    try:
        import transformers
        print(f"\ntransformers version: {transformers.__version__}")
    except Exception as e:
        print(f"\n❌ Failed to import transformers: {e}")
        all_valid = False
    
    # Check TRL version
    try:
        import trl
        print(f"trl version: {trl.__version__}")
    except Exception as e:
        print(f"❌ Failed to import trl: {e}")
        all_valid = False
    
    # Check PEFT version
    try:
        import peft
        print(f"peft version: {peft.__version__}")
    except Exception as e:
        print(f"❌ Failed to import peft: {e}")
        all_valid = False
    
    # Test SFTConfig (replaces TrainingArguments in newer TRL)
    try:
        from trl import SFTConfig
        
        # Key params we use
        expected = {
            'output_dir',
            'num_train_epochs',
            'per_device_train_batch_size',
            'per_device_eval_batch_size',
            'gradient_accumulation_steps',
            'learning_rate',
            'bf16',
            'logging_steps',
            'eval_steps',
            'save_steps',
            'lr_scheduler_type',
            'warmup_ratio',
            'report_to',
            'max_length'  # SFT-specific
        }
        
        # Check for eval_strategy (new) vs evaluation_strategy (old)
        sig = inspect.signature(SFTConfig.__init__)
        actual_params = set(sig.parameters.keys())
        
        if 'eval_strategy' in actual_params:
            expected.add('eval_strategy')
            print("\n  ℹ️  Using 'eval_strategy' (new API)")
        elif 'evaluation_strategy' in actual_params:
            expected.add('evaluation_strategy')
            print("\n  ℹ️  Using 'evaluation_strategy' (old API)")
        else:
            print("\n  ⚠️  Neither eval_strategy nor evaluation_strategy found!")
            all_valid = False
        
        if not check_api_params(SFTConfig.__init__, expected, "SFTConfig"):
            all_valid = False
            
    except Exception as e:
        print(f"\n❌ SFTConfig validation failed: {e}")
        import traceback
        traceback.print_exc()
        all_valid = False
    
    # Test SFTTrainer
    try:
        from trl import SFTTrainer
        
        sig = inspect.signature(SFTTrainer.__init__)
        actual_params = set(sig.parameters.keys())
        
        print(f"\nSFTTrainer:")
        print(f"  Available params: {sorted(actual_params)}")
        
        # Check which tokenizer param is supported
        if 'processing_class' in actual_params:
            print("  ℹ️  Using 'processing_class' for tokenizer (new API)")
            expected = {'model', 'train_dataset', 'eval_dataset', 'args', 'processing_class'}
        elif 'tokenizer' in actual_params:
            print("  ℹ️  Using 'tokenizer' (old API)")
            expected = {'model', 'tokenizer', 'train_dataset', 'eval_dataset', 'args'}
        else:
            print("  ⚠️  Neither processing_class nor tokenizer found!")
            all_valid = False
            expected = {'model', 'train_dataset', 'eval_dataset', 'args'}
        
        if not check_api_params(SFTTrainer.__init__, expected, "SFTTrainer (required params)"):
            all_valid = False
            
    except Exception as e:
        print(f"\n❌ SFTTrainer validation failed: {e}")
        import traceback
        traceback.print_exc()
        all_valid = False
    
    # Test LoraConfig
    try:
        from peft import LoraConfig
        
        expected = {
            'r',
            'lora_alpha',
            'lora_dropout',
            'target_modules',
            'task_type'
        }
        
        if not check_api_params(LoraConfig.__init__, expected, "LoraConfig"):
            all_valid = False
            
    except Exception as e:
        print(f"\n❌ LoraConfig validation failed: {e}")
        all_valid = False
    
    # Test model loading
    try:
        from transformers import AutoModelForCausalLM, AutoTokenizer
        print("\n✅ AutoModelForCausalLM and AutoTokenizer imported successfully")
    except Exception as e:
        print(f"\n❌ Failed to import model/tokenizer classes: {e}")
        all_valid = False
    
    # Print summary
    print("\n" + "=" * 70)
    if all_valid:
        print("✅ ALL VALIDATIONS PASSED")
        print("=" * 70)
        return 0
    else:
        print("❌ SOME VALIDATIONS FAILED")
        print("=" * 70)
        return 1


if __name__ == "__main__":
    sys.exit(main())

