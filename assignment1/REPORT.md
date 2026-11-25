# Assignment 1: Multi-Environment Infrastructure Deployment with Terraform

## Introduction

This assignment extends the Week 1-6 pipeline into a multi-environment deployment on an AWS Academy account. The Lab 6 Terraform (two EC2 instances and a security group) was refactored into one reusable module, `assignment1/terraform/modules/web`, and called three times from `dev/`, `staging/` and `prod/`. A single GitHub Actions workflow (`.github/workflows/assignment1.yml`) validates every pull request, applies staging automatically on merge to `main`, and applies prod only after a named reviewer approves. No long-lived AWS credentials exist anywhere: the pipeline uses the session-scoped Academy credentials, stored as environment-scoped secrets and refreshed each lab session. An application value (a placeholder database password) lives in SSM Parameter Store and is read by Terraform through a data source, and each environment has a CloudWatch alarm defined in Terraform. All evidence is in `assignment1/evidence/`.

| Evidence file | What it shows |
|---|---|
| `backend-state-keys.txt` | three distinct state keys in the S3 bucket |
| `environments.json` | staging and prod protection rules |
| `secrets-scope.txt` | no repository-level AWS secrets; all three in each environment |
| `prod-approval-pending.png` / `prod-approval-approved.png` | the prod gate waiting, then approved |
| `staging-apply.txt` / `prod-apply.txt` | the pipeline's apply logs |
| `ssm-parameter.txt` | the parameters and Terraform reading them |
| `cloudwatch-alarm.json` / `cloudwatch-alarm.png` | the alarms in the OK state |
| `destroy-complete.txt` | teardown of all three environments |

## Reusable module

The module is `assignment1/terraform/modules/web` (`main.tf`, `variables.tf`, `outputs.tf`). I extracted it because the same resources were about to be written a third time, once per environment.

**Inputs** (all typed; the first three are validated):

- `environment`: must be `dev`, `staging` or `prod`. It is used in every resource name and tag.
- `instance_count`: 1 to 3, because the term budget is $50.
- `instance_type`: `t3.micro` or `t3.small`.
- `instance_profile`: defaults to `LabInstanceProfile`, which the Academy account already provides.
- `cpu_alarm_threshold`: defaults to 70.

**Outputs:** `instance_ids`, `public_ips`, `security_group_id`, `alarm_names` and `db_password_length`.

Every resource name includes the environment (for example `acs730-a1-prod-sg`), because all three environments live in one Academy account and fixed names would collide. The security group allows port 80 in and nothing else: there is deliberately no port 22 rule and no key pair. The AMI is found with `data "aws_ami"` so that the only `aws_ssm_parameter` in the project is the password. I used `count` for the instances because they are identical and only their number differs; `for_each` would be the better choice if they were distinguished by keys.

## Environment directories

`dev/`, `staging/` and `prod/` each contain a `backend.tf` and a `main.tf` that call the same module. They differ only in the values they pass: dev and staging run one instance, prod runs two. Each directory has its own state key in the same bucket (`acs730-tfstate-615313524491`):

- `assignment1/dev/terraform.tfstate`
- `assignment1/staging/terraform.tfstate`
- `assignment1/prod/terraform.tfstate`

The backend uses `encrypt = true` and `use_lockfile = true`. I changed the key in the same edit as copying each directory and checked it with `grep` before the first `init`.

I chose separate directories over Terraform workspaces because a reviewer can see which environment a change touches: a prod change appears as `prod/` in the pull request's changed-files list, whereas with workspaces the files are identical and the difference is invisible. A wrong command is also visible in the shell prompt. Workspaces would be defensible for a solo operator, but they are a poor fit for a reviewed, automated pipeline pointed at a real account.

## GitHub Environments

Two environments exist in the repository (`environments.json`):

- **staging** has no reviewer. A push to `main` applies it automatically.
- **prod** has one required reviewer, a deployment branch policy that allows only `main`, and "allow administrators to bypass" switched off, so the approval cannot be skipped.

In the workflow, the `staging` job runs only on a push to `main` and needs `validate`. The `prod` job needs `staging` and declares `environment: prod`, so it pauses for approval. Pull requests run only `validate` and `credcheck`, so no PR can reach staging or prod.

## Scoped credentials and OIDC trust policy

The three AWS secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) were moved from repository level to environment scope on staging and prod, and the repository-level copies were deleted. `secrets-scope.txt` shows the repository section empty and all three names in each environment. I confirmed the move before deleting: the `credcheck` job (which declares `environment: staging`) passed, and it passed again when re-run after the repository-level secrets were deleted, so it was reading the environment secrets. The per-session refresh from now on is:

    ./scripts/refresh-gha-creds.sh Aldo-JCampos/acs730-labs staging prod

The old two-argument form would still exit successfully but would refresh repository-level secrets that no workflow can read.

Environment scope means only a job that declares the environment can read these secrets, and for prod that means a job that has passed the reviewer gate and the `main`-only branch policy. A limit of this setup: in Academy, staging and prod hold the same credentials for the same account and role, so scoping controls who can read them, not what they can do. In a real account the roles would be separate. For the same reason, the `staging` job also runs `terraform plan` against prod so the reviewer can read the plan before approving; that works here only because there is one account, and in a real account that read-only plan would need its own scoped role.

### Trust policy I would deploy in a real account

This was not deployed: IAM writes are denied in the Learner Lab, and the account provides only the existing role. This is the policy I would attach to the prod role (the account ID is illustrative):

    {
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": {
          "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringEquals": {
            "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
            "token.actions.githubusercontent.com:sub": "repo:Aldo-JCampos/acs730-labs:environment:prod"
          }
        }
      }]
    }

What each part prevents:

- **`Principal.Federated`** names GitHub's OIDC provider registered in this account. Only tokens signed by that issuer can be exchanged. IAM users, other identity providers and unauthenticated callers are rejected.
- **`Action: sts:AssumeRoleWithWebIdentity`** allows the role to be obtained only by exchanging a web-identity token. Ordinary `sts:AssumeRole` from AWS principals is not permitted by this policy.
- **`aud = sts.amazonaws.com`** requires the token to have been issued for AWS STS. A token minted for another service or audience cannot be replayed here.
- **`sub = repo:Aldo-JCampos/acs730-labs:environment:prod`** is the important one. GitHub builds `sub` from how the job was triggered. A job that declares `environment: prod` carries the `environment:prod` form. A job without an environment carries a branch or pull-request form such as `repo:.../acs730-labs:ref:refs/heads/<branch>`. Pinning `sub` therefore means other repositories and forks, the staging job, and any branch or pull-request job are all refused. It also ties the role to the gates: the only way to obtain a token with this `sub` is to run a job in the prod environment, which requires the reviewer's approval and a run from `main`.
- **`StringEquals` instead of `StringLike`** means no wildcard can match, so a value like `repo:Aldo-JCampos/acs730-labs:*` would not be accepted.

**What a repo-wide wildcard would allow.** With a `sub` of `repo:Aldo-JCampos/acs730-labs:*`, anyone with push access to any branch could add a workflow that does not declare an environment, request a token, and assume the prod role directly. That skips the reviewer approval and the branch policy entirely, because those rules apply only to jobs that declare the environment. The environment-pinned `sub` closes that route. It still depends on the environment's own rules being intact, which is why administrator bypass is switched off.

## Real deployment

I opened pull request #19. `validate` and `credcheck` passed, and the `staging` and `prod` jobs were skipped, as designed for a pull request. After the merge to `main` (commit `762f076`), workflow run `45641690377` did the following:

1. `validate` passed in 32 seconds.
2. `staging` applied automatically with no human involved: `Plan: 3 to add` then `Apply complete! Resources: 3 added` (15:09 UTC), in 44 seconds.
3. The `staging` job also printed the prod plan, `Plan: 5 to add, 0 to change, 0 to destroy`, with nothing to be replaced. I read it while the gate was waiting.
4. `prod` stayed in "Waiting for review". I captured the waiting state in `prod-approval-pending.png`, then approved and captured `prod-approval-approved.png`.
5. `prod` applied: `Plan: 5 to add` then `Apply complete! Resources: 5 added` (15:14 UTC), in 35 seconds. The whole run took 6 minutes 50 seconds.

The three state files appear in the bucket (`backend-state-keys.txt`). Dev was applied from the workstation; staging and prod were created by the pipeline.

## Secrets management

The application value is a placeholder database password at `/acs730/<environment>/db_password` in SSM Parameter Store, stored as a `SecureString` under the default AWS-managed key. I created it once by hand before any plan that reads it, as a documented pre-step (the value is a throwaway placeholder):

    aws ssm put-parameter --name /acs730/<env>/db_password --type SecureString --value '<placeholder-value>' --overwrite

Terraform only reads it, through `data "aws_ssm_parameter" "db_password"` in the module. There is no `aws_ssm_parameter` resource anywhere: if Terraform both created and read the same parameter, that would be circular, and it would fail on a fresh environment where the parameter does not yet exist, which is exactly what CI does. Leaving the pre-step out would fail the plan the same way. As proof the value was read without printing it, the module outputs only its length (21), and the apply logs show `Read complete` for the data source and contain no password text.

This solves a different problem from the credentials above. OIDC or environment secrets answer how the pipeline proves who it is to AWS. They do not answer where the running application gets its database password, which is what Parameter Store is for. The value lives in the store, and the code holds only its name. I chose Parameter Store over Secrets Manager because it is free at the standard tier and I need no automatic rotation here; Secrets Manager's rotation and RDS integration would justify its cost for a real database. One unavoidable leak remains: the value read by the data source ends up in `terraform.tfstate`. I contain that with an encrypted state bucket (`encrypt = true`) and by never committing state (`.gitignore` excludes it).

## CloudWatch alarm

Each environment has one alarm per instance, defined in the module (`aws_cloudwatch_metric_alarm.cpu_high`). It watches `AWS/EC2` `CPUUtilization` (average, 5-minute periods) and fires above 70% for two consecutive periods. I chose CPU because an idle instance still reports it, so the alarm has real datapoints; a request-count metric on a server nobody calls would stay at no data. After several evaluation periods all four alarms (`dev`, `staging`, and `prod` `-0` and `-1`) were in the `OK` state (`cloudwatch-alarm.json`, `cloudwatch-alarm.png`). The alarm has no notification action, since no SNS topic was in scope; in production it would notify an on-call channel.

## Recommendation

For a team fully committed to AWS with no multi-cloud plans, I would recommend an AWS-native pipeline (CodePipeline with CodeBuild) over this GitHub Actions pipeline. Three concrete factors decide it.

**1. Where the identity lives.** In this assignment, getting AWS credentials to the pipeline was the hardest part. I paste session credentials into three secrets in two environments, refresh them every session, found that the refresh command silently changed form halfway, and had to write an OIDC trust policy to describe what a real account would do. In an AWS-native pipeline the build runs under an IAM service role that the service assumes itself. There is no token exchange to scope and no secret to store or refresh, and CloudTrail attributes every action to that role. Pinning `sub` correctly is a skill; a role the service assumes removes the mistake.

**2. Reaching private resources.** GitHub-hosted runners come from the public internet. They cannot reach a private subnet, a private database or a VPC endpoint. In Lab 6 I had to route around this with Session Manager. Self-hosted runners fix it, but then I patch and secure them. CodeBuild can run inside the VPC, so the day the team needs to apply against something private, nothing changes.

**3. Runner cost and upkeep.** GitHub-hosted runners were free for this public repository, but for a private repository the free minutes run out and environment protection rules require a paid plan (this assignment's own prerequisite). CodeBuild is billed per build minute, there is nothing to patch, and the approval step (a manual approval action) is controlled by IAM permissions, which a team already manages.

**What this gives up.** GitHub Actions is tied tightly to the pull-request workflow, has a large marketplace of ready-made actions, and the whole team already knows it; its environment gates were quick to set up and clear to read. If the team lived in GitHub and used OIDC with disciplined role scoping, Actions would be a reasonable choice. For an AWS-only team, though, the identity, private-network and upkeep factors outweigh that familiarity.

## Conclusion

I now have a working path from a pull request to a gated production deployment. The module is written once and parameterised, the three state keys keep the environments from colliding, staging deploys by itself, and prod waits for a person. The credentials are scoped to the environments that need them, and the application's secret never appears in code or logs.

Several things went wrong in ways that taught more than the parts that worked. The Lab 6 workflow had no remote state, so the runner built a second set of instances. The workstation ran out of disk because every `terraform init` downloaded its own 675 MB copy of the AWS provider, which a shared plugin cache fixed. And the refresh script's environment creation failed for lack of a token permission, which I worked around by creating the environments by hand and giving the token the narrower Environments permission instead of Administration.

If I did it again, I would apply the exact saved plan that the reviewer read rather than re-planning in the prod job, and I would use separate roles per environment in any real account. The reviewer reads a plan, but the job approves and applies a fresh one, so in principle they could differ.

Teardown of all three environments is recorded in `destroy-complete.txt`.
