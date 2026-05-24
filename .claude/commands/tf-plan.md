---
description: Run terraform fmt, validate, and a read-only plan, then summarize the diff
---

Run the following, in order, and summarize the results for me:

1. `terraform fmt -recursive` — report any files reformatted.
2. `terraform validate` — surface any configuration errors.
3. `terraform plan -no-color` — summarize resources to add / change / destroy. Call out anything destructive explicitly.

Do not run `terraform apply` or `terraform destroy`.
