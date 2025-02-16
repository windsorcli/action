# action
A Github Action for installing the Windsor CLI

## Usage
  ```yaml
  - name: Install Windsor CLI
    uses: windsorcli/action/.github/actions/windsorcli@v0.0.1
    with:
      version:           ${{ inputs.version }}
      install_folder:    ${{ github.workspace }}/${{ inputs.install_folder }}
      context:           ${{ inputs.context }}
  ```

