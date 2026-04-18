# GitHub-Driven Dev Destroy

## Purpose

This folder is meant to enable a GitHub Actions workflow to destroy the `dev`
environment in AWS without depending on a local machine staying online.

The practical goal is simple:

- trigger a CI job
- let GitHub run the destroy flow in the cloud
- close the laptop at the end of the day without waiting for the teardown to
  finish

This matches the project rule that demo environments should be created only when
needed and destroyed after use.

## Working Rule

This README is the source of truth for this isolated destroy automation effort.

From this point onward:

- the plan for this feature must be documented here
- every meaningful implementation step must be reflected here
- the file should always describe both what is already done and what still
  remains

## Agreed Design

We explicitly decided to build this in an additive-only way.

That means:

- do not modify the base Terraform stacks in `envs/dev`
- do not modify the shared IAM/OIDC module for this feature
- do not modify `scripts/destroy-dev.sh` for the first version
- create a dedicated Terraform folder only for the remote destroy IAM role
- later add a dedicated GitHub Actions workflow file that uses that role and
  runs the existing destroy script

The main reason for this decision is isolation: the remote destroy feature
should not change the core project structure more than necessary.

## What This Stack Creates

This Terraform stack creates a dedicated IAM role for GitHub Actions:

- role name: `calculator-github-actions-destroy-dev`
- auth method: GitHub OIDC (`AssumeRoleWithWebIdentity`)
- allowed caller:
  `repo:haimNemir/calculator_IaC_Terra:ref:refs/heads/main`

The stack also stores its Terraform state in the shared S3 backend under:

- `automation/github-destroy-dev/terraform.tfstate`

## Why This Exists

The repository already has a local destroy script at
`scripts/destroy-dev.sh`. That script is designed to tear down the `dev`
environment aggressively and safely enough for demo usage.

The missing convenience was remote execution.

Instead of running the destroy locally and keeping the computer awake until the
AWS teardown finishes, the intended flow is:

1. Start a GitHub Actions workflow manually.
2. GitHub assumes this IAM role through OIDC.
3. GitHub runs the destroy flow.
4. The local computer can be turned off immediately.

## Progress So Far

The work is intentionally still partial.

What we already completed:

- we evaluated two approaches:
  - make the local destroy flow resumable
  - move the destroy execution to GitHub Actions
- we decided to explore the GitHub Actions model first
- we decided to keep the implementation isolated from the base Terraform code
- we rejected an earlier version that changed shared/base project files too much
- we created this dedicated folder for the isolated implementation
- we added Terraform code in this folder for a dedicated GitHub OIDC destroy
  role
- the role trust policy is restricted to this repository and the `main` branch
- the role currently attaches `AdministratorAccess`
- the local destroy implementation already exists in
  `scripts/destroy-dev.sh`, and the current plan is to reuse it rather than
  rewrite destroy logic inside CI
- we added a dedicated workflow file at
  `.github/workflows/destroy-dev-remote.yml`
- the workflow is manual (`workflow_dispatch`) and is designed to:
  - run only from `main`
  - assume `calculator-github-actions-destroy-dev`
  - prepare kubeconfig if the cluster still exists
  - run `scripts/destroy-dev.sh`
  - upload the destroy log as a GitHub Actions artifact
- the isolated Terraform stack was applied in AWS
- the role `calculator-github-actions-destroy-dev` now exists in AWS
- the role currently has `AdministratorAccess` attached as planned

What is intentionally not done yet:

- there is no committed end-to-end CI path yet that starts from
  `workflow_dispatch` and finishes with a full remote destroy.
- the workflow and this automation folder are still local changes until they are
  committed, pushed, and merged to `main`

## Current Plan

The plan from here is:

1. Keep this implementation isolated inside this folder plus one future
   workflow file in `.github/workflows/`.
2. Apply the Terraform stack in this folder so AWS gets the dedicated GitHub
   role.
3. Commit and push the workflow plus this automation folder to GitHub.
4. Merge those changes into `main`, because both the workflow and the IAM trust
   policy are intended to work from `main`.
5. Test the workflow end to end from GitHub after the IAM role exists.
6. Later decide whether to keep `AdministratorAccess` or replace it with a
   narrower policy.

## How To Apply This Stack

Run these commands from this folder:

```bash
cd /mnt/c/Users/Haim/Documents/Projects/Calculator/calculator_IaC_Terra/automation/github_destroy_dev
terraform init -reconfigure
terraform plan
terraform apply
```

After apply, collect the role ARN:

```bash
terraform output role_arn
```

## Intended CI Execution Flow

The planned GitHub Actions flow should look like this:

1. Manual trigger with `workflow_dispatch`.
2. Workflow permissions include:
   `id-token: write` and `contents: read`.
3. Use `aws-actions/configure-aws-credentials` to assume the role created by
   this folder.
4. Check out this repository.
5. Run `scripts/destroy-dev.sh`.
6. Let GitHub keep running until the destroy completes, even if the laptop is
   already off.

## Remaining Work

The remaining implementation work is mainly:

- commit and push the new workflow and automation folder
- merge them into `main`
- make sure the workflow can successfully assume
  `calculator-github-actions-destroy-dev` from GitHub
- keep the workflow on top of `scripts/destroy-dev.sh` instead of duplicating
  destroy logic in YAML
- test the workflow from GitHub end to end
- decide whether to keep `AdministratorAccess` for the role temporarily or
  replace it later with a narrower least-privilege policy

## Important Note

The role currently attaches `AdministratorAccess`. That is workable for an
initial destroy automation path, but the proper long-term direction is to
replace it with a narrower policy once the exact destroy actions are stable and
known.
