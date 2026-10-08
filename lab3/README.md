# Lab 3

Instructions for this section will be provided in class and on Blackboard when we reach it.

Put your work for Lab 3 in this folder.

Why a real account would use OIDC: A real account should use OIDC federation because the workflow trades a short-lived identity token for temporary credentials at run time, so no long-lived access key is ever stored, rotated, or left behind to leak, and the trust policy can restrict access to a specific repository, branch, or environment.

Why this course uses session-scoped secrets: This course uses session-scoped secrets because configuring an identity provider and trust policy would take more setup than the exercise is about, and if they leak the damage is limited because they expire when the session ends and are granted only the minimal permissions in a disposable sandbox account.
