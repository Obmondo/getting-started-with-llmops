# Getting started with LLMOps

## The hardware

The biggest threshold for self hosting an LLM is hardware, i.e., GPU memory (VRAM).

Let's calculate approximately how much VRAM is required to run the
[google/gemma-4-12B-it-qat-w4a16-ct](https://huggingface.co/google/gemma-4-12B-it-qat-w4a16-ct)
model with **256K context window size** :

- According to [vLLM's documentation](https://github.com/vllm-project/recipes/blob/main/Google/Gemma4.md#quantized-models-qat-w4a16),
  the weights themselves consume **8.3GB**.

- For a **256K sized context window**, you need around **5GB of VRAM**.
  > You can calculate it yourself using
  > [this formula provided by FastGPU](https://fastgpu.co/blog/llm-vram-guide).

- Additional VRAM is required for the vLLM inference engine to run.

**16GB of VRAM** might lead us to OOM issues. So, a GPU with **24GB of VRAM**
seems to be a safer bet.

Buying an `RTX 3090` with **24 GB GDDR6X VRAM** and **936 GB/s bandwidth**
[currently costs nearly 1,500 USD](https://www.spheron.network/gpu-price/rtx-3090/).
Plus, you need to pay for the rest of the system : CPU, RAM, motherboard etc.

> [`Apple Silicon`'s `System on Chip (SoC)` architecture with the `Unified Memory
> Model (UMA)`](https://developer.apple.com/videos/play/wwdc2020/10686/) makes it
> more affordable to get a computer with 24GB of VRAM.
>
.
>
> The twist is : it's shared between both the CPU and GPU. And, the memory
> bandwidth is much lower; **273 GB/s** provided by an `M4 Pro` compared to the
> **936 GB/s** provided by an `RTX 3090`.

[vast.ai](https://vast.ai/) is a platform connecting compute providers, from
hobbyists to Tier-4 datacenters, with users who need GPUs. And, I'll be using
that to rent the required hardware temporarily for really cheap.

## The software

From the hardware perspective, as decided above, we'll be having only a single
server with a 24GB GPU VRAM. However, we'll design the software stack in such a
way, that we can include more servers in the hardware layer with minimal effort.
We'll be using the following :

- [NVIDIA GPU Operator](https://github.com/NVIDIA/gpu-operator) : automates the
  management of all NVIDIA software components needed to use GPUs from within
  Kubernetes.

- [NVSentinel](https://github.com/NVIDIA/NVSentinel) : automatically detects,
  classifies, and remediates hardware and software faults in GPU nodes.

- [HAMi](https://github.com/project-hami/hami) : enables sharing a single GPU
  across multiple containers and workloads.

- [KServe](https://github.com/kserve/kserve) : makes it easier to run the LLMs
  using an inference engine like vLLM.

- [LMCache](https://github.com/lmcache/lmcache) : is used to manage a durable KV
  cache layer.

- [Hindsight](https://github.com/vectorize-io/hindsight) : organizes knowledge
  into a hierarchy of facts and consolidated knowledge.

## References

- [Open source AI gateways compared](https://vercel.com/i/open-source-ai-gateways)

- [Production-Grade LLM Inference at Scale with KServe, llm-d, and vLLM](https://kserve.github.io/website/blog/production-grade-llm-inference-kserve-llm-d-vllm)

- [Pi vs Hermes vs Codex vs Claude Code: Which AI Agent Fits?](https://mcplato.com/en/blog/pi-agent-hermes-codex-claude-code-mcplato/)
