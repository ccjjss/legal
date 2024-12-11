provider "aws" {
  region  = "us-east-1"
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "local_file" "iam_policy_file" {
  filename = "iam_policy.json"
  content = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:*",
        "ec2:Describe*",
        "ec2:Get*",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "iam:GetPolicy",
        "iam:ListAttachedRolePolicies",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:CreateServiceLinkedRole",
        "iam:GetRole",
        "iam:ListRolePolicies",
        "iam:GetRolePolicy",
        "waf-regional:GetWebACL",
        "waf-regional:AssociateWebACL",
        "waf-regional:DisassociateWebACL",
        "wafv2:GetWebACL",
        "wafv2:AssociateWebACL",
        "wafv2:DisassociateWebACL",
        "shield:GetSubscriptionState",
        "shield:DescribeProtection",
        "shield:CreateProtection",
        "shield:DeleteProtection"
      ],
      "Resource": "*"
    }
  ]
}
EOT
}

resource "aws_iam_policy" "alb_controller_policy" {
  name        = "ALBControllerPolicy"
  description = "IAM policy for ALB Controller"
  policy      = local_file.iam_policy_file.content
}

resource "aws_iam_role" "alb_controller_role" {
  name               = "alb-controller-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "alb_controller_attachment" {
  role       = aws_iam_role.alb_controller_role.name
  policy_arn = aws_iam_policy.alb_controller_policy.arn
}

resource "kubernetes_service_account" "alb_controller_sa" {
  metadata {
    name      = "alb-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller_role.arn
    }
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  chart      = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = "lega-eks"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.alb_controller_sa.metadata[0].name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "region"
    value = "us-east-1"
  }

  depends_on = [kubernetes_service_account.alb_controller_sa]
}

