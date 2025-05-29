# Windsor CLI GitHub Action

This GitHub Action installs and configures the Windsor CLI for use in GitHub Actions workflows.

## Inputs

### `version`
- **Description**: The version of Windsor CLI to install
- **Required**: No
- **Default**: `v0.5.7`

### `ref`
- **Description**: Git reference to build Windsor CLI from source instead of downloading a release. Requires Go to be installed.
- **Required**: No
- **Default**: `""` (empty string)
- **Example**: `main`, `v0.5.6`, `1234abc`

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

### `verbose`
- **Description**: Enable verbose logging for debugging purposes
- **Required**: No
- **Default**: `"false"`

### `install-only`
- **Description**: Only install the CLI without initializing context or injecting environment variables
- **Required**: No
- **Default**: `"false"`

## Usage

```yaml
steps:
  - name: Install Windsor CLI
    uses: windsorcli/action@v1
    with:
      version: v0.5.7
      context: local
      workdir: .windsor/.tf_modules/cluster/talos
```

## Security Considerations

### Verbose Mode Warning
⚠️ **Important**: When using `verbose: true`, the action will log detailed information including:
- Environment variables
- Command outputs
- File paths
- System information

This can potentially expose sensitive information in your workflow logs. Only enable verbose mode when debugging issues and disable it in production workflows.

### Secrets Protection
- Never use verbose mode in workflows that handle sensitive data
- Be cautious when using verbose mode with workflows that have access to secrets
- Review workflow logs carefully when verbose mode is enabled

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
          version: v0.5.7
          context: local
          workdir: terraform/cluster/eks
          # verbose: true  # Only enable for debugging
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
