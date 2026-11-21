# Lab 6: Ansible configuration management and a Packer golden AMI

Terraform builds two tagged EC2 instances with no port 22 ingress. An Ansible role (dynamic inventory, idempotent playbook, Session Manager connection) configures them. The same role is baked into a golden AMI with Packer, and a GitHub Actions workflow runs the converge immediately after `terraform apply`.

## Required sentences

- **Runner-to-instance mechanism:** I used AWS Systems Manager Session Manager, because the instances have no port 22 open at all and no private key is stored anywhere, so a runner with a changing address can reach them without a stored credential or a firewall rule.
- **What changed=0 on a second run proves:** The playbook did nothing on the second run because every task checked the real state of the host and found it already matched what the role asks for, which is what makes it safe to run on every merge.
- **Why deregistering an AMI is not enough:** Deregistering removes the AMI pointer, but the EBS snapshot behind it is the stored data and the part that bills, so it has to be deleted separately.

## Design choices

**Terraform (lab6/terraform/main.tf)**
- No port 22 rule and no key pair: the SSM agent on Amazon Linux 2023 dials out to Systems Manager over 443, so the instances need only outbound internet. The security group allows port 80 in and everything out.
- `iam_instance_profile = "LabInstanceProfile"` attaches the profile the Academy account already has. Attaching is an EC2 call; creating a role or profile is an IAM write, which the Academy denies.
- The tags `Lab=lab6` and `Role=web` are the contract with Ansible: the dynamic inventory finds instances by these tags, so changing them in Terraform without changing the inventory leaves it empty.
- The AMI id comes from the public SSM parameter for Amazon Linux 2023, because Amazon rebuilds the image and the id changes. `instance_count` defaults to 2, so that two hosts prove the inventory is dynamic.
- Terraform state, `.terraform/`, plans and `.pem` files are in `.gitignore` before the first apply.

**Dynamic inventory (ansible/inventory/lab6.aws_ec2.yml)**
- The amazon.aws.aws_ec2 plugin only loads files whose names end in `aws_ec2.yml`, hence the filename. It filters on `tag:Lab=lab6` and `instance-state-name=running`, so terminated instances are not listed.
- `hostnames: instance-id` because Session Manager connects by instance id, not by IP. `keyed_groups` on `tags.Role` with prefix `role` builds the group `role_web`. No ids or addresses are written down anywhere.
- It sits in `inventory/` so the grading pipeline treats everything there as configuration. The SSM connection settings live in `group_vars/role_web.yml`, so they apply only to that group, not to localhost or a Packer build instance.

**Playbook and role**
- Every task uses a module with its full name (`ansible.builtin.dnf`, not `dnf`) and YAML-dict arguments, with modes quoted (`"0644"`), so behaviour does not depend on which collections are installed and YAML cannot turn a mode into a number.
- `hosts: all` because the inventory and `-l` decide which machines run; Packer hands the play a build instance that belongs to no group.
- `state: present` for packages (already true next time) rather than `latest`. The service restart is a handler, which fires once only when the unit file changed. The last task uses `state: started`, not `restarted`, which is true on later runs.
- The role keeps variables in `defaults/main.yml` because defaults have the lowest precedence, so callers can override them; Packer overrides `build_tag` with `--extra-vars`. The two templates moved into `roles/webserver/templates/` and `site.yml` shrank to a four-line play.

**Packer (packer/web.pkr.hcl)**
- `required_plugins` is needed because Packer has had no built-in builders since 1.7; without it `init` fetches nothing and `validate` fails with "Unknown builder type".
- Every variable has a default because `validate` does not read the shell environment. The base image is chosen with `source_ami_filter`, not a data source, so `validate` works offline.
- `use_proxy = false` and `--scp-extra-args '-O'` make the Ansible provisioner work with current OpenSSH. `--extra-vars build_tag=golden-ami` makes the baked page say which path produced it.
- `baked.html` is copied in after the role has run, so the role never manages it.
- **Packer vs a stored key:** Packer creates a per-build key pair and a temporary security group for its throwaway instance, which opens port 22 briefly during the build, and deletes both when the build ends. That is ephemeral and scoped to one run. A long-lived private key in repository secrets, or a standing 0.0.0.0/0 rule on port 22, would be a stored credential and a permanent opening.

**GitHub Actions workflow (.github/workflows/lab6-configure.yml)**
- No runner address anywhere in the file: there is no checkip lookup, no `ssh_cidr` and no rule rewritten per run, because the runner never needs to be let in; the connection is opened outwards through Session Manager.
- The tooling is installed near the top, not between apply and converge, so nothing sits between "apply" and "converge".
- The SSM Session Manager plugin is installed explicitly. It is a native binary that pip does not provide, and a clean runner does not have it; the failure otherwise is "SessionManagerPlugin is not found" and only appears in CI.
- A retry loop (pinging the hosts up to 30 times) runs before the playbook, because `terraform apply` returns when EC2 says the instance is running, which is before the SSM agent registers.
- Apply is manual only (`workflow_dispatch` with `apply: true`) and the push trigger is scoped to `lab6/**`, so a push only plans. There is deliberately no SSH key secret.

## Measured boot-to-ready times

| Path | Seconds | What it includes |
|---|---|---|
| Converge-on-boot | 221 | Terraform destroying and recreating the instance (about 43 s), boot, SSM agent registration, dnf install, templates, service start |
| Golden AMI | 77 | Instance launch, boot, service start (everything else was baked in) |

The golden AMI was 144 seconds (about 65%) faster per launch. The converge figure also includes Terraform destroying the old instance, which the golden launch did not; even without that, the AMI path is still roughly twice as fast.

**Where the time went.** For converge-on-boot, the slow part was most likely waiting for the SSM agent to register and then dnf downloading packages over the network on each instance, not the Ansible logic itself. I did not time each phase separately, so this is the likely explanation, not a measurement.

**The cost of a golden AMI moves rather than disappears.** The same work still happens, but once at build time instead of on every instance at launch. The Packer build took about 3 minutes 25 seconds, and each launch saves about 144 seconds, so the image pays for itself from the second instance onward.

**What breaks with golden AMIs.** An image is frozen: updates released after the bake are not in it, so I need a rebuild cadence, and I cannot see inside it without reading the build log, whereas a playbook is its own documentation.

**What breaks with converge-on-boot.** Every launch depends on package mirrors being reachable at that moment, so a mirror outage means instances that boot but never become ready, and autoscaling at 3 a.m. is exactly when I do not want a network dependency in the boot path.

**Recommendation.** Golden AMI, unless I only ever launch one or two instances or the configuration changes more often than I am willing to rebake the image.

## SSM bucket and region constraint

The aws_ssm connection stages file transfers through an S3 bucket I own (`acs730-lab6-ssm-<account id>`). The bucket's region and `ansible_aws_ssm_region` must be the same (us-east-1 here), or the first task fails with PermanentRedirect. The connection plugin ships in the community.aws collection (9.x here, since amazon.aws 10 and later require ansible-core 2.17 or newer and this workstation has 2.15.3).

## Experiments

**Experiment 1: breaking idempotency.**
*Prediction:* Adding `ansible.builtin.shell: mkdir -p /opt/acs730-web/logs` makes run 2 show `changed=1` on each host, because the shell module cannot inspect state and always reports changed. After adding `creates: /opt/acs730-web/logs` I expected `changed=0`, because the directory already exists, so the command would not run.
*Result:* I added the task and the second run still reported `changed=1` per host, as predicted. Ansible cannot work out what a shell command would change, so it reports `changed` every time. Adding `creates:` gave it a state check, and the next run dropped to `changed=0` because the command did not run, since the path already existed. I removed the task afterwards and re-confirmed `changed=0`.

**Experiment 2: `state: latest` vs `present`.**
*Prediction:* Changing the dnf task to `latest` shows `changed=0` on both runs today, because Amazon Linux 2023's repos are locked to the AMI's release version. But this depends on upstream, not on my code, so it could change on any day another release ships.
*Result:* Both runs reported `changed=0`. In a pipeline that runs on every merge I would still use `present`: with `latest`, whether a run reports `changed` depends on what upstream published that day rather than on my code, so a change in the recap stops meaning "something drifted from the playbook" and packages can be upgraded without review. "Always up to date" is not obviously better, because patching still matters, but I would handle it deliberately, for example by rebuilding the golden AMI on a schedule, so each upgrade is reviewed and repeatable. I reverted the change and re-confirmed `changed=0`.

## Evidence (lab6/evidence/)

`inventory-graph.txt`, `idempotency-run1.txt`, `idempotency-run2.txt`, `pipeline-run.png`, `golden-ami.png`, `teardown.txt`, plus the timing files `boot-to-ready-ansible.txt` and `boot-to-ready-golden.txt` and the build log `packer-build.txt`.
