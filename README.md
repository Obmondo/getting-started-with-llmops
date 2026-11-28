# Getting started with LLMOps

## The hardware

The biggest threshold for self hosting an LLM is hardware, i.e., GPU memory (VRAM).

Let's calculate approximately how much VRAM is required to run the [google/gemma-4-12B-it-qat-w4a16-ct](https://huggingface.co/google/gemma-4-12B-it-qat-w4a16-ct) model with **256K context window size** :

- According to [vLLM's documentation](https://github.com/vllm-project/recipes/blob/main/Google/Gemma4.md#quantized-models-qat-w4a16), the weights themselves consume **8.3GB**.

- For a **256K sized context window**, you need around **5GB of VRAM**.
  > You can calculate it yourself using [this formula provided by FastGPU](https://fastgpu.co/blog/llm-vram-guide).

- Additional VRAM is required for the vLLM inference engine to run.

**16GB of VRAM** might lead us to OOM issues. So, a GPU with **24GB of VRAM** seems to be a safer bet.

Buying an `RTX 3090` with **24 GB GDDR6X VRAM** and **936 GB/s bandwidth** [currently costs nearly 1,500 USD](https://www.spheron.network/gpu-price/rtx-3090/). Plus, you need to pay for the rest of the system : CPU, RAM, motherboard etc.

> [`Apple Silicon`'s `System on Chip (SoC)` architecture with the `Unified Memory Model (UMA)`](https://developer.apple.com/videos/play/wwdc2020/10686/) makes it more affordable to get a computer with 24GB of VRAM.
>
.
>
> The twist is : it's shared between both the CPU and GPU. And, the memory bandwidth is much lower; **273 GB/s** provided by an `M4 Pro` compared to the **936 GB/s** provided by an `RTX 3090`.

[vast.ai](https://vast.ai/) is a platform connecting compute providers, from hobbyists to Tier-4 datacenters, with users who need GPUs. And, I'll be using that to rent the required hardware temporarily for really cheap.

## The instance

When you create an instance in vast.ai, you don't get a VM, but rather a container. We'll use the `docker.io/vastai/kvm:@vastai-automatic-tag` container image provided by vast.ai to have a [Linux KVM](https://linux-kvm.org/page/Main_Page) inside the container. vast.ai provides a template marketplace where people can share instance launch configurations. You can use [this template](https://cloud.vast.ai?ref_id=454384&template_id=3e2313118117db7928b2ffdcf971e2ba) to create an instance.

Since we'll be using [fp8]((https://docs.vllm.ai/en/stable/features/quantization/llm_compressor/fp8/)) dtype for the `KVCache`, we require atleast `NVIDIA RTX 5090` to meet the minimum `NVIDIA compute capability` requirement of `5.9`.

> Every NVIDIA GPU has a Compute Capability (CC) number, which indicates what features are supported by that GPU and specifies some hardware parameters for that GPU.
> REFER https://docs.nvidia.com/cuda/cuda-programming-guide/01-introduction/cuda-platform.html#compute-capability-and-streaming-multiprocessor-versions.

Once the instance gets created, you can SSH and run `nvidia-smi` to confirm that a GPU with the expected Compute Capability and VRAM is attached.

## The cluster

Navigate to `./manifests/environments/default` and execute `kubeone apply -m cluster.yaml` to initialize the Kubernetes cluster.

> During the `kubeadm` installation  step, if you get an error complaining that a process (an unattented upgrade running, since [automatic updates](https://ubuntu.com/server/docs/how-to/software/automatic-updates/) are enabled by default) is holding the apt lock, SSH into the server and kill that process.

KubeOne will create a kubeconfig file in that working directory. You need to modify the Kubernetes API server address :

- Change the IPv4 address to the public IPv4 address of the vast.ai instance.

- Change the port to whatever value the `VAST_TCP_PORT_6443` environment variable has in the vast.ai instance.
  > Port exposure from the vast.ai instance isn't straightforward. Port 6443 gets mapped to a higher port, whose value is stored in that environment variable.

## The software

## References

- [Open source AI gateways compared](https://vercel.com/i/open-source-ai-gateways)

- [Production-Grade LLM Inference at Scale with KServe, llm-d, and vLLM](https://kserve.github.io/website/blog/production-grade-llm-inference-kserve-llm-d-vllm)

- [Pi vs Hermes vs Codex vs Claude Code: Which AI Agent Fits?](https://mcplato.com/en/blog/pi-agent-hermes-codex-claude-code-mcplato/)

- [Hindsight vs Cognee: AI Agent Memory Comparison (2026)](https://vectorize.io/articles/hindsight-vs-cognee)
