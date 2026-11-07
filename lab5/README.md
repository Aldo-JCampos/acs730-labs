# Lab 5 - Terraform network on AWS or LocalStack

One configuration that builds a public network (VPC, two subnets, internet
gateway, route table, associations, security group) plus an EC2 web server.
`use_localstack` decides whether it targets real AWS or a LocalStack container.

## Why for_each here and count there

- **Subnets use for_each** because they are distinct things with stable names.
  Add key "c" and the plan is "1 to add, 0 to change, 0 to destroy"; remove "a"
  and it is "1 to destroy", with "b" untouched.
- **The same subnets with count would be a trap.** Addresses would be [0], [1],
  [2]; delete the middle entry and everything after it shifts down a slot, so
  Terraform compares public[1] in state against a different subnet in config
  and plans to destroy and recreate two subnets just to remove one.
- **The bucket uses count** because the input is a yes/no about one resource:
  exactly two plans, "0 to add" and "1 to add", and no key to be stable about.
  In short: count when the question is how many, for_each when the question
  is which ones.

## What I built

One Terraform configuration in lab5/ that builds a public VPC, two subnets
(for_each), an internet gateway, a route table with associations, and a
dynamic-block security group, plus an EC2 web server with user_data and an
optional count-gated bucket. `use_localstack` switches one provider block
between real AWS and a LocalStack container. A two-job GitHub Actions
workflow runs fmt/validate first, then a plan/apply/destroy against a
LocalStack service container, with no AWS credentials. I broke it on purpose,
confirmed the required check blocked the merge, then fixed it.

## Why not plan and apply against real AWS on every pull request

- **It costs money per run, not per month.** Every pull request builds and
  destroys real infrastructure. 27 students pushing a few times each is
  thousands of cycles against one fixed $50 pot. LocalStack costs nothing and
  leaves nothing behind.
- **It needs a long-lived AWS credential in the repository.** Applying from
  Actions means an access key in GitHub secrets, which can leak and must be
  rotated, and in an Academy account you cannot scope it, because IAM writes
  are denied, so the only key that works is a broad one.
- **Academy sessions expire.** Lab credentials last hours, so a pull request
  opened on Saturday night fails on Sunday morning for a reason unrelated to
  the code, and people learn to ignore red checks. A check people ignore is
  worse than no check.
- **It is slow and flaky.** Minutes each way, API rate limits,
  eventual-consistency errors unrelated to your change, and concurrent pull
  requests colliding on names and state in one account.
- **Be honest about the limit.** A green LocalStack run proves the
  configuration is coherent and the graph builds, not that IAM is right
  (LocalStack does not enforce it) or that user_data works (LocalStack never
  boots the instance). The real check belongs on merge or on a schedule,
  once, not per pull request.
