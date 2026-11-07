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
