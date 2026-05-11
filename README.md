# Aeges Static

Static install entrypoint for Aeges.

This repository is intended to host:

- `https://get.aeges.top/`
- `https://get.aeges.top/install.sh`
- `https://get.aeges.top/install.ps1`

The CLI package itself remains published from the main Aeges repository through
GitHub Releases. The static installer scripts download versioned `.nupkg`
artifacts and verify `SHA256SUMS` before installing the global .NET tool.

## DNS

Point `get.aeges.top` at GitHub Pages for this repository.

The deployed site includes:

```text
public/CNAME
```

with:

```text
get.aeges.top
```

## Deploy

Push to `production`. GitHub Actions publishes the contents of `public/` to
GitHub Pages.

## Local Preview

Any static file server works:

```bash
python3 -m http.server 8080 --directory public
```

Open:

```text
http://localhost:8080
```
