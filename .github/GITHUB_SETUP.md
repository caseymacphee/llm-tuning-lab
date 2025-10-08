# GitHub Secrets and Variables Setup

This document describes what needs to be configured in GitHub for CI/CD.

## Required GitHub Secret

### AWS_GHA_ROLE_ARN

**Type:** Repository Secret (sensitive)

**How to get the value:**
```bash
cd infra/envs/training
terraform output github_actions_role_arn
```

**How to set in GitHub:**
1. Go to your repository on GitHub
2. Click **Settings** (in repository, not your profile)
3. Click **Secrets and variables** → **Actions**
4. Click **New repository secret**
5. Name: `AWS_GHA_ROLE_ARN`
6. Value: Paste the output from Terraform (e.g., `arn:aws:iam::123456789012:role/llm-tuning-lab-github-actions-role`)
7. Click **Add secret**

**Why it's secret:** This ARN grants access to push Docker images to your ECR repository. While the ARN itself isn't highly sensitive, keeping it as a secret prevents others from knowing your AWS account ID and infrastructure setup.

## No Other Secrets Required! 🎉

This setup uses **OpenID Connect (OIDC)** which means:
- ✅ No AWS Access Keys needed
- ✅ No AWS Secret Access Keys needed
- ✅ No static credentials stored in GitHub
- ✅ Temporary credentials generated on-demand by AWS STS
- ✅ More secure than long-lived credentials

## How OIDC Works

1. GitHub Actions requests credentials from AWS
2. AWS validates the request using OIDC
3. AWS issues temporary credentials (valid ~1 hour)
4. GitHub Actions uses these credentials
5. Credentials expire automatically

The role ARN tells AWS which role to assume when GitHub Actions makes the request.

## Verifying Setup

After setting the secret, trigger the workflow:

```bash
git commit --allow-empty -m "Test GitHub Actions"
git push origin main
```

Then:
1. Go to **Actions** tab in GitHub
2. Click on the running workflow
3. Check if it succeeds

If it fails with authentication errors:
- Double-check the secret value matches Terraform output
- Ensure you've run `terraform apply` to create the OIDC provider and role
- Check that the repository owner/name matches what's in `infra/modules/training-registry/variables.tf`

## Optional: GitHub Variables (Non-Sensitive)

If you want to make the ECR repository name configurable without hardcoding in the workflow:

**Settings** → **Secrets and variables** → **Actions** → **Variables** tab

None are required currently, but you could add:
- `AWS_REGION` (default: us-west-2)
- `ECR_REPOSITORY` (default: llm-tuning-lab-training)

These are public and visible to anyone with repo access.

## Security Best Practices

### ✅ Do:
- Use repository secrets for sensitive values
- Regularly rotate credentials (OIDC does this automatically)
- Limit OIDC role permissions to minimum required
- Review GitHub Actions logs for any exposed secrets

### ❌ Don't:
- Commit secrets to the repository
- Use personal AWS access keys in GitHub
- Share secrets across multiple repositories
- Log secret values in GitHub Actions

## Troubleshooting

### Error: "Unable to locate credentials"

**Problem:** Secret not set or incorrect

**Fix:**
```bash
# Get the correct value
cd infra/envs/training
terraform output github_actions_role_arn

# Update the GitHub secret with this exact value
```

### Error: "User is not authorized to perform: sts:AssumeRoleWithWebIdentity"

**Problem:** OIDC provider or role not configured correctly

**Fix:**
```bash
# Ensure Terraform has created the OIDC resources
cd infra/envs/training
terraform plan  # Check if any OIDC resources need to be created
terraform apply
```

### Error: "Access Denied" when pushing to ECR

**Problem:** IAM role doesn't have ECR push permissions

**Fix:**
```bash
# Re-apply Terraform to ensure IAM policies are correct
cd infra/envs/training
terraform apply -auto-approve
```

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ GitHub Actions Workflow                                     │
│                                                              │
│  1. Push to main branch                                     │
│  2. Request credentials from AWS                            │
│     ├─ Uses: AWS_GHA_ROLE_ARN secret                       │
│     └─ AWS validates via OIDC provider                     │
│  3. AWS STS issues temporary credentials                    │
│  4. Build Docker image                                      │
│  5. Push to ECR                                             │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ AWS Infrastructure (via Terraform)                          │
│                                                              │
│  ┌─────────────────────────────────────────────────┐       │
│  │ OIDC Provider (token.actions.githubusercontent.com)│      │
│  └─────────────────────────────────────────────────┘       │
│                            │                                 │
│                            ▼                                 │
│  ┌─────────────────────────────────────────────────┐       │
│  │ IAM Role: llm-tuning-lab-github-actions-role    │       │
│  │   Trust: GitHub repo (OIDC)                     │       │
│  │   Permissions: ECR push                         │       │
│  └─────────────────────────────────────────────────┘       │
│                            │                                 │
│                            ▼                                 │
│  ┌─────────────────────────────────────────────────┐       │
│  │ ECR Repository: llm-tuning-lab-training         │       │
│  │   Contains: Docker images for training          │       │
│  └─────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

## References

- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS IAM OIDC](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [Terraform aws_iam_openid_connect_provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider)


