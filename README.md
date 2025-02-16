# action
A Github Action for installing the Windsor CLI

## Usage
  ```yaml
  - name: Install Windsor CLI
    uses: windsorcli/action/.github/actions/windsorcli@v0.0.1
    with:
      windsorcli_version:           ${{ inputs.windsorcli_version }}
      windsorcli_branch:            ${{ inputs.windsorcli_branch }}
      windsorcli_install_folder:    ${{ github.workspace }}/${{ inputs.windsorcli_install_folder }}
      use_release:                  ${{ inputs.use_release }}
      os:                           ${{ matrix.runner.os }}
      arch:                         ${{ matrix.runner.arch }}
  ```

