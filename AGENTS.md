# AGENTS Guide for scGPT

## 1. Scope and Priorities
This guide focuses on:
- model architecture and objective heads
- data preprocessing/tokenization/collation contracts
- end-to-end data-to-model wiring for training and embedding inference

It is intentionally not benchmark-focused and does not duplicate paper-level results.

## 2. High-Level Repository Layout
Core paths for model/data work:
- `scgpt/`: package root for preprocessing, tokenization, trainer utilities, and model modules.
- `scgpt/model/`: transformer backbones and task-specific model variants (`model.py`, `generation_model.py`, `multiomic_model.py`).
- `scgpt/tokenizer/`: gene vocabulary and sequence tokenization/padding helpers.
- `scgpt/tasks/`: higher-level task entrypoints (for example cell embedding and GRN utilities).
- `examples/finetune_integration.py`: canonical fine-tuning pipeline example.

Supporting folders:
- `tutorials/`: usage notebooks, including zero-shot workflows.
- `tests/`: lightweight test coverage.
- `docs/`: documentation site sources.

## 3. End-to-End Data Pipeline
Primary data path (training/fine-tuning style):
1. Load counts into `AnnData`.
2. Build/align gene naming metadata (`adata.var["gene_name"]` or task-specific gene column).
3. Preprocess with `scgpt.preprocess.Preprocessor`:
- optional gene/cell filtering
- library-size normalization
- optional log1p
- optional HVG subsetting
- optional per-cell quantile binning into discrete expression bins
4. Build/align gene vocabulary using `GeneVocab` (pretrained vocab or task vocab).
5. Convert matrix to token sequences with tokenizer helpers:
- `tokenize_batch(...)`
- `tokenize_and_pad_batch(...)`
6. Apply random masking to expression values for MLM-style objectives (`random_mask_value`).
7. Build PyTorch datasets/loaders via `scgpt.trainer.prepare_data(...)` and `prepare_dataloader(...)`.

Inference/embedding path (`scgpt.tasks.cell_emb`):
1. Load `AnnData` and model artifacts (`args.json`, `vocab.json`, `best_model.pt`).
2. Map genes to vocab ids and filter out OOV genes.
3. Build per-cell non-zero gene/value sequences with `<cls>` prefix.
4. Collate/pad sequences via `DataCollator`.
5. Run encoder and use `<cls>` embedding as cell representation; write to `adata.obsm["X_scGPT"]`.

## 4. Tokenization and Collation Contracts
Tokenizer semantics (`scgpt/tokenizer/gene_tokenizer.py`):
- Gene expressions are represented as `(gene_id, value)` sequences, usually sparse (non-zero genes only).
- Special tokens (commonly `<pad>`, `<cls>`, `<eoc>`) must exist in vocab for training/inference paths.
- `tokenize_and_pad_batch(...)` returns padded batched tensors (`genes`, `values`, optional modality labels).

Batch collation semantics (`scgpt/data_collator.py`):
- Pads/truncates to configured max sequence length.
- Optionally samples tokens when sequence is too long.
- Can bin expression values at collate time.
- Applies MLM masking only on non-pad tokens and protects initial special-token prefix (`keep_first_n_tokens`).

## 5. Model Pipeline (Architecture Side)
Base model entrypoint: `scgpt.model.model.TransformerModel`.

Forward pipeline:
1. Gene token embedding (`GeneEncoder`).
2. Value embedding (`ContinuousValueEncoder` or categorical encoder, depending on config).
3. Optional batch-conditioning path (`BatchLabelEncoder`, DSBN/batchnorm options).
4. Transformer encoder stack (PyTorch transformer or flash-attn-backed fast path when enabled).
5. Task decoders:
- expression reconstruction (`ExprDecoder`, MLM/GEP)
- optional masked value prediction for cell embedding (`MVCDecoder`, GEPC)
- optional classification head (`ClsDecoder`, CLS)
- optional domain-adversarial branch (`AdversarialDiscriminator`, DAB)
6. Optional explicit zero-probability modeling through Bernoulli outputs.

Additional model variants:
- `generation_model.py`: perturbation-aware generator (`TransformerGenerator`) with perturbation flag embeddings.
- `multiomic_model.py`: multi-omic-specific model variant and modality handling.

## 6. Runtime and Task Wiring
General runtime helpers are in `scgpt/trainer.py`:
- `prepare_data(...)`: masked input/target construction and task-label tensor assembly.
- `prepare_dataloader(...)`: standard or subset-aware batch sampling (`SubsetsBatchSampler`).
- `train(...)` / `evaluate(...)` / `test(...)`: epoch loop and metric wiring for supported tasks.

Task families expected by training helpers:
- `annotation`
- `integration`
- `perturb`
- `multiomic`

Dedicated utility task entrypoints:
- `scgpt/tasks/cell_emb.py`: embedding extraction APIs for AnnData.
- `scgpt/tasks/grn.py`: downstream gene embedding similarity/graph utilities.

## 7. Model-Data Interface Contract
Stable assumptions across core paths:
- Inputs are expression matrices that can be represented as non-negative per-cell gene values.
- Gene axis must align with the active vocabulary; OOV genes are dropped in embedding paths.
- Sequence tensors use:
- `gene_ids`: token ids with special tokens
- `values`: expression/bin values aligned to `gene_ids`
- `src_key_padding_mask`: derived from pad token id
- Pad semantics are explicit (`pad_token`, `pad_value`) and must be consistent between tokenization and model config.
- Task-specific labels (`batch_labels`, `celltype_labels`, `mod_types`) are optional but required when corresponding objectives are enabled.

Checkpoint/config contract commonly used by examples and task APIs:
- `vocab.json`
- `args.json`
- `best_model.pt`

## 8. Practical Caveats
- Flash-attention is optional; fast path silently falls back if backend is unavailable.
- Sequence length and sparsity decisions (`include_zero_gene`, HVG selection, max length) materially affect memory and behavior.
- Some paths are GPU-oriented (mixed precision and CUDA-first defaults in examples).
- Pretrained checkpoint assets are external to source tree and must be staged separately.

## 9. Suggested Agent Workflow
When modifying architecture/data behavior:
1. Start from `examples/finetune_integration.py` to identify active preprocessing/tokenization settings.
2. Validate assumptions in `scgpt/preprocess.py` and `scgpt/tokenizer/gene_tokenizer.py`.
3. Trace model behavior through `scgpt/model/model.py` (or generation/multiomic variant as relevant).
4. Confirm runtime wiring in `scgpt/trainer.py` and task API impacts in `scgpt/tasks/cell_emb.py`.
5. Run a small end-to-end smoke path (tokenize -> one train/eval step or embedding extraction) after changes.
