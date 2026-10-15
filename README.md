# Conda Environment Tunnel Deploy

Deploy one Conda environment from an Internet-connected relay server to an offline container through a reverse SSH tunnel opened by a Windows PC.

The workflow intentionally exposes only two commands:

```powershell
.\open-tunnel.ps1
```

```bash
./deploy-conda-env.sh ENV_NAME
```

See [README_KO.md](README_KO.md) for setup, configuration, replacement safety, and optional Miniconda bootstrap instructions.
