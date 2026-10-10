# Lab 3

Instructions for this section will be provided in class and on Blackboard when we reach it.

Put your work for Lab 3 in this folder.

Why a real account would use OIDC: A real account should use OIDC federation because the workflow trades a short-lived identity token for temporary credentials at run time, so no long-lived access key is ever stored, rotated, or left behind to leak, and the trust policy can restrict access to a specific repository, branch, or environment.

Why this course uses session-scoped secrets: This course uses session-scoped secrets because configuring an identity provider and trust policy would take more setup than the exercise is about, and if they leak the damage is limited because they expire when the session ends and are granted only the minimal permissions in a disposable sandbox account.

## Troubleshooting

**ExpiredToken on a deploy**
Your lab session ended, so the AWS credentials stored in GitHub expired.
Start a new lab session, re-run `refresh-gha-creds.sh`, then re-run the
failed job. Nothing in the repository changes.

**"Input required and not supplied: aws-region"**
The `AWS_REGION` GitHub variable does not exist. This is not a credential
problem. Run the refresh script, or set it directly:
`gh variable set AWS_REGION --body us-east-1`

## Terraform version

Terraform v1.10.3

## Experiments

### Experiment 1 - Removing S3 backend
**Prediction:** Removing the S3 backend would switch Terraform to local state. A GitHub Actions runner couldn’t see that state and might try to create a resource that already exists.

**Result:** After I removed the backend and ran terraform init -migrate-state, Terraform offered to copy the existing state locally. I said yes, and it created a local terraform.tfstate containing my AWS resource.

### Experiment 2 - Expired AWS credentials
**Prediction:** Once my AWS lab session ended, the temporary credentials would expire, and the GitHub Actions workflow would fail at authentication with an ExpiredToken error.

**Result:**After ending my Vocareum session, the workflow failed during terraform init with a 403 Forbidden error when accessing the S3 state file. I restarted the lab, refreshed the credentials, and reran the workflow, which succeeded with no changes. No repository files needed to be modified.
