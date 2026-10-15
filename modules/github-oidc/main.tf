############################################################
# GitHub Actions -> AWS without stored access keys (OIDC)
#
#  1. IAM trusts GitHub's token issuer (the OIDC provider)
#  2. A role says: "only workflows of THIS repo, on THIS branch, may assume me"
#  3. The role may only push images to the listed ECR repositories
############################################################

locals {
  issuer_host  = "token.actions.githubusercontent.com"
  provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
  tags         = merge(var.tags, { Project = "CloudNative-Mesh", ManagedBy = "Terraform" })
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://${local.issuer_host}"
  client_id_list = ["sts.amazonaws.com"]
  tags           = local.tags
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://${local.issuer_host}"
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # The "sub" claim identifies exactly which repo and branch the workflow runs on.
    # Pull requests carry a different sub (repo:...:pull_request), so they can NOT assume this role.
    condition {
      test     = "StringEquals"
      variable = "${local.issuer_host}:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/${var.branch}"]
    }
  }
}

resource "aws_iam_role" "ci" {
  name                 = var.name
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600
  tags                 = local.tags
}

data "aws_iam_policy_document" "push" {
  # Logging in to ECR is an account-level action and cannot be scoped to a repository
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_role_policy" "push" {
  name   = "ecr-push"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.push.json
}
