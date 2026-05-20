// Terraform scaffold: GitHub Actions IAM role (least-privilege example)
// NOTE: Customize policy ARNs and resource ARNs before applying.

resource "aws_iam_role" "github_actions" {
  name = "cs3-github-actions-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          },
          StringLike = {
            // Restrict to specific repository and branch
            "token.actions.githubusercontent.com:sub" = "repo:MiroBG/cs3:ref:refs/heads/main"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "github_actions_policy" {
  name = "cs3-github-actions-policy"
  path = "/"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "sts:AssumeRole",
          "s3:*",
          "dynamodb:*",
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "eks:DescribeCluster",
          "secretsmanager:GetSecretValue"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_policy.arn
}

data "aws_caller_identity" "current" {}
