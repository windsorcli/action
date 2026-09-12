# Windsor CLI GitHub Action

This GitHub Action installs and configures the Windsor CLI for use in GitHub Actions workflows.

## Inputs

### `ref`
- **Description**: Git reference to build Windsor CLI from source, or a release tag to download. `nightly` downloads the latest build from `main`.
- **Required**: No
- **Default**: Latest stable release
- **Example**: `main`, `v1.0.0`, `nightly`, `1234abc`

### `context`
- **Description**: The context to use for Windsor CLI commands
- **Required**: No
- **Default**: `"local"`
- **Example**: `"production"`, `"staging"`

### `workdir`
- **Description**: The working directory for Windsor CLI commands
- **Required**: No
- **Default**: `""` (current directory)
- **Example**: `".windsor/.tf_modules/cluster/talos"`

### `install-only`
- **Description**: Only install the CLI without initializing context or injecting environment variables
- **Required**: No
- **Default**: `"false"`

### `inject-secrets`
- **Description**: Whether to inject decrypted secrets into environment variables
- **Required**: No
- **Default**: `"false"`

## Caching

Building the CLI from a non-release `ref` (a branch or commit SHA) is cached automatically — no input needed.

## Usage

```yaml
steps:
  - name: Install Windsor CLI
    uses: windsorcli/action@v1
    with:
      ref: v1.0.0
      context: local
      workdir: .windsor/.tf_modules/cluster/talos
```

## Sub-actions

Once the CLI is installed (the root action above, or `install-only: true` if you don't need context init / env injection), a set of sub-actions wrap common windsor commands so a workflow doesn't need to hand-write `run: windsor ...` steps. Each one:

- Expects `windsor` already on PATH — it doesn't install the CLI itself, and fails fast with an actionable message if it can't find one.
- Takes an optional `workdir` input, resolved the same way as the root action's.
- Emits a `context` output (the value of `windsor get context` after the command runs), so a later step can label an artifact or log line without an extra call.

### `windsorcli/action/up`

Wraps `windsor up`.

| Input | Description |
| --- | --- |
| `wait` | Block until kustomizations report ready (`--wait`) |
| `vm-driver` | `--vm-driver` |
| `platform` | `--platform` |
| `blueprint` | `--blueprint` |
| `set` | Config overrides, one `key=value` per line, repeated as `--set` |

```yaml
- uses: windsorcli/action/up@v1
  with:
    wait: true
    set: |
      cluster.workers.count=3
```

### `windsorcli/action/apply`

Wraps `windsor apply`. `terraform-component` and `kustomize-name` scope to a single layer, matching `windsor apply terraform <component>` / `windsor apply kustomize <name>` — they're mutually exclusive, and `wait`/`prune` aren't valid once scoped to `terraform-component` (that subcommand has neither flag).

| Input | Description |
| --- | --- |
| `wait` | Block until kustomizations report ready (`--wait`) |
| `prune` | Remove kustomizations the blueprint no longer declares (`--prune`) |
| `terraform-component` | Scope to one terraform component |
| `kustomize-name` | Scope to one kustomization |

```yaml
- uses: windsorcli/action/apply@v1
  with:
    wait: true
    prune: true
```

### `windsorcli/action/destroy`

Wraps `windsor destroy`. `confirm` is required — `windsor destroy` always asks for confirmation, and there's no TTY in CI to answer it, so this is the non-interactive equivalent of typing the expected token at the prompt.

| Input | Description |
| --- | --- |
| `confirm` | **Required.** Context or component name to confirm destruction |
| `component` | Destroy a single component instead of everything |
| `layer` | Scope to one layer: `""` (both), `terraform`, or `kustomize` |
| `continue` | Continue past per-component failures and report a summary (`--continue`, layer-wide only) |

```yaml
- uses: windsorcli/action/destroy@v1
  with:
    confirm: ${{ steps.setup.outputs.context }}
```

### `windsorcli/action/bootstrap`

Wraps `windsor bootstrap`. `yes` is required for the same reason `destroy`'s `confirm` is: `windsor bootstrap` prompts for confirmation with no way to detect a non-interactive caller on its own.

| Input | Description |
| --- | --- |
| `yes` | **Required.** Skip confirmation prompts (`--yes`) — pass `"true"` to proceed non-interactively |
| `context` | Context to bootstrap (defaults to the current context) |
| `platform` | `--platform` |
| `blueprint` | `--blueprint` (OCI reference) |
| `set` | Config overrides, one `key=value` per line, repeated as `--set` |

```yaml
- uses: windsorcli/action/bootstrap@v1
  with:
    context: staging
    platform: aws
    blueprint: oci://ghcr.io/myorg/blueprint:v1.0.0
    yes: true
```

### `windsorcli/action/check`

Wraps `windsor check` — verifies required tools and cloud credentials. Takes only `workdir`.

```yaml
- uses: windsorcli/action/check@v1
```

### `windsorcli/action/plan-comment`

Runs `windsor plan --summary --no-color` and posts the result as a sticky PR comment — updating the same comment on later pushes rather than piling up a new one each time. The comment is matched by a hidden marker keyed on the windsor context name, so a matrix of contexts posting to the same PR each get their own comment instead of overwriting one another.

Requires `permissions: pull-requests: write` on the calling job. Defaults to the triggering PR (`github.event.pull_request.number`), so it's meant for a `pull_request`-triggered workflow; pass `pr-number` to use it elsewhere. A failed `windsor plan` still gets posted (with the real error, so reviewers can see what happened) — the step then fails afterwards so the job goes red.

| Input | Description |
| --- | --- |
| `component` | Scope to a single component (both layers), like `windsor plan <component>` |
| `pr-number` | Override the PR number (defaults to `github.event.pull_request.number`) |
| `github-token` | Token used to read/write the comment (defaults to `github.token`) |

```yaml
permissions:
  pull-requests: write

steps:
  - uses: windsorcli/action/plan-comment@v1
```

## Recipes

Patterns worth documenting without owning the extra code as a built-in input.

### Caching Terraform providers across runs

windsor never sets `TF_PLUGIN_CACHE_DIR` itself — it passes through whatever the environment already has to every `terraform` it runs. Set it yourself and cache the directory:

```yaml
- name: Set up Terraform provider cache
  run: |
    mkdir -p "$RUNNER_TEMP/tf-plugin-cache"
    echo "TF_PLUGIN_CACHE_DIR=$RUNNER_TEMP/tf-plugin-cache" >> "$GITHUB_ENV"

- uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0
  with:
    path: ${{ runner.temp }}/tf-plugin-cache
    key: ${{ runner.os }}-tf-providers-${{ hashFiles('**/.terraform.lock.hcl') }}
    restore-keys: |
      ${{ runner.os }}-tf-providers-

- uses: windsorcli/action@v1
  # ... your windsor apply / up / etc. steps
```

If you don't commit `.terraform.lock.hcl` files, `hashFiles` resolves to an empty string and every run shares one cache keyed just by OS — still correct (Terraform verifies each provider's checksum before using it), just less precisely scoped than a lockfile-keyed cache.

## Security

The action automatically detects and masks secrets in your workflow:

1. Detects environment variables in your windsor.yaml that use the `${{ }}` syntax
2. Uses GitHub Actions' built-in secret masking to prevent secrets from appearing in logs
3. Only logs variable names, never their values
4. Maintains a minimal logging footprint to reduce potential information exposure
5. Reduces the threat surface by only using [actions/github-script](https://github.com/actions/github-script) with a pinned SHA

NOTE: When using third party actions, you should ALWAYS reference them explicitly by their SHA. Furthermore, it's expected that you have performed your own threat modeling on systems in which this mechanism is used. See [Security hardening for GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions) for more information.

## Example Workflow

```yaml
name: CI

on:
  push:

jobs:
  windsorcli:
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
    runs-on: ${{ matrix.os }}
  
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.11.4
          terraform_wrapper: false

      - name: Install Windsor CLI
        uses: ./
        with:
          ref: v1.0.0
          context: local
          workdir: terraform/cluster/eks
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
