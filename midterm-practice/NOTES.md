# Notes

Removing a file or credential in a new commit does not remove it from the repository, because git keeps every earlier commit, so anyone can still recover the old state file and secret from history, and the credential must be treated as compromised and rotated.
