# Local LLM stack

Two units that are easy to lose on a reinstall and annoying to re-derive.

## `ollama-override.conf` → `/etc/systemd/system/ollama.service.d/override.conf`

This is **hardware tuning**, not preference. Strix Halo has no discrete VRAM split
worth using here — inference runs on the iGPU (`card1`) over Vulkan, not on the
RX 9070 XT eGPU:

| Variable | Why |
|---|---|
| `OLLAMA_VULKAN=1` | Vulkan backend rather than ROCm |
| `AMD_VULKAN_ICD=RADV` | force RADV over AMDVLK |
| `OLLAMA_IGPU_ENABLE=1` | allow the integrated GPU as a target at all |
| `GGML_VK_VISIBLE_DEVICES=1` | device 1 = the iGPU; keeps inference off the eGPU |
| `OLLAMA_KEEP_ALIVE=-1` | never unload a model — deliberate, 125 GB of RAM |

`KEEP_ALIVE=-1` means a loaded model stays resident permanently. That is the
intended behaviour on this box; on a machine with less RAM, change it to a
duration like `30m`.

## `open-webui.service` → `~/.config/systemd/user/open-webui.service`

Runs as a user unit, always on, reachable on the LAN at `:8080`.

Non-obvious bits, all of which were learned the hard way:

- **`DATA_DIR` is deliberately outside the pipx venv.** The default lives under
  `site-packages/open_webui/data`, which `pipx upgrade open-webui` replaces
  wholesale — taking all chat history with it.
- **`WorkingDirectory=/home/nate`** keeps `~/.webui_secret_key` resolving to the
  same file manual launches used, so existing logins survive.
- **`ReadWritePaths` on the venv static dir** — Open WebUI re-copies branding
  assets into the frontend static dir on every start; read-only there logs 19
  errors per boot.
- **`DEFAULT_MODELS` is a PersistentConfig.** It is read from the environment
  only when the key is absent from `webui.db`; after that the DB value wins
  (`ui.default_models`). The env var is there so a rebuilt DB comes back with the
  right default rather than none.

## No cloud, by design

The reason this stack exists is that nothing leaves the box — Claude is the cloud
model. Hardening applied 2026-09-13:

- `openai.enable` → `false` in `webui.db`. It was on by default, pointed at
  `api.openai.com`, with no key set. Inert, but on.
- `OFFLINE_MODE=True` plus `ENABLE_VERSION_UPDATE_CHECK`, `ANONYMIZED_TELEMETRY`,
  `DO_NOT_TRACK` and `SCARF_NO_ANALYTICS`. Open WebUI was holding a live
  connection to a CloudFront host on a default install; it no longer opens any
  external socket.
- `qwen3.5:cloud` removed from ollama.

`OFFLINE_MODE` is only safe because `all-MiniLM-L6-v2` is already in
`~/.cache/huggingface` (889 MB). Turn it off temporarily if you ever need to pull
a different embedding model, then turn it back on.

Verify with:

```sh
ss -tnp | grep open-webui | grep -vE '127\.0\.0\.1|192\.168\.'   # expect nothing
```

## Models kept

`qwen3.8:27b` (default) and `qwen3.5:122b-a10b`. Pruned 2026-09-13 from 266 GB
down to 93 GB by removing four models untouched for two months, plus the
`qwen3.5:cloud` pointer.
