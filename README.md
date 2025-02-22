# action
A Github Action for installing the Windsor CLI

## Usage
  ```yaml
  - name: Install Windsor CLI
    uses: windsorcli/action/.github/actions/windsorcli@vX.Y.Z
    with:
      version:           # When set, the action will install the version using the binary installation method.
      ref:               # When set, overrides the version and installs the ref. using the source installation method.
      install_folder:    # The folder to install the Windsor CLI (windsor or windsor.exe)
      context:           # The context to use for the windsor commands
      workdir:           # The working directory for the windsor commands
  ```

## Notes

- The action will install the Windsor CLI in the `install_folder` directory.
- The action will set the context for the windsor commands to the `context` value.
- The action will run the windsor commands in the `workdir` directory.
- The action will use the `version` or `ref` value to install the Windsor CLI.
- The action detects if windsor is already installed and skips the installation if it is.
- The action detects if windsor init has already been run and skips it if it has.