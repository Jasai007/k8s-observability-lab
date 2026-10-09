# GitHub Actions workflows

This folder contains the CI automation for the repository.

## Workflow files

### `ci.yml`

Runs the same validation script used locally:

```bash
bash scripts/validate.sh
```

The workflow is triggered on:
- push
- pull request
- manual dispatch via the Actions tab

It performs the following checks:
- checks out the repository
- installs the Go toolchain for `apps/demo-api`
- installs `kubectl` so Kustomize checks can run in CI
- installs PyYAML for YAML parsing validation
- runs the repository validation script

## Local validation

Use the same command locally before pushing changes:

```bash
bash scripts/validate.sh
```

This keeps CI and local developer checks aligned.
