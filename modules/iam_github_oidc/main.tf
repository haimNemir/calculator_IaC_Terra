data "aws_caller_identity" "current" {}  # Get the current AWS account ID

resource "aws_iam_openid_connect_provider" "github" {      # Create inside IAM an OIDC provider for GitHub Actions. This allows GitHub Actions to authenticate with AWS using OIDC tokens. This mean that if GitHub Actions will create a token to connect to AWS, AWS will trust that token and allow connections from GitHub Actions.
  url = "https://token.actions.githubusercontent.com"      # This URL is the endpoint for GitHub Actions OIDC tokens. When GitHub Actions requests a token, it will be issued by this provider (This a endpoint of GitHub Actions also), and AWS will validate it against this URL. 

  client_id_list = [                                       # Here we specify who can use this OIDC provider, in this case is the STS service of AWS that decodes the OIDC token and allows GitHub Actions to assume the IAM role we will create later. 
    "sts.amazonaws.com",
  ]

  thumbprint_list = [                                      # In the console this value defined by default. This allow to AWS to save the "finger print" of the server that connects to the AWS, and if the server will change the connection will be rejected. This is a security measure 
    "6938fd4d98bab03faadb97b34396831e3780aea1",            # To get this "Fingerprint" you can check the documentation of AWS for GitHub OIDC. 
  ]
}

data "aws_iam_policy_document" "assume_role" {             # This data is not a ordinary "data", that just pull information from exist resource in AWS. Here this data create locally a JSON document that define the a group of rules for the IAM role we will create later in the resource "aws_iam_role" "github_actions" below.
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]            # This policy allow the role to be assumed (assumed means that another entity can use this out AWS account to do actions) by a web identity such as GitHub Actions token.

    ## Allows outside identity to get access to AWS resources.
    principals {                                           # Principals in IAM define who can assume the role. In this case we specify that the principal is a federated identity provider, which is the OIDC provider we created above for GitHub Actions. This means that only entities that can authenticate with this OIDC provider (GitHub Actions) can assume this role.
      type        = "Federated"                            # Federated is the opposite of internal AWS user or service. This means that the principal is for external identity such as GitHub Actions.
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    # Conditions in IAM policies allow to specify additional rules that must be met for the policy to take effect.
    ## Check for audience.
    condition {                                            # In this case we check the audience in "values" var, that must be "sts.amazonaws.com" word-for-word. And we define the "test" as "StringEquals", which means that the condition will be true if the audience in the token is exactly "sts.amazonaws.com". 
      test     = "StringEquals"                            # "StringEquals" = word-for-word, without regex.
      variable = "token.actions.githubusercontent.com:aud" # This variable returns the claim in the OIDC token - the "audience" claim. And this claim we check that it is equal to "sts.amazonaws.com".
      values   = ["sts.amazonaws.com"]
    }
    ## Check for repository and ref (branch or tag).
    condition {
      test     = "StringLike"                              # "StringLike" = Allows for use regex, such as "..tags/v*" to match all tags that start with "v".
      variable = "token.actions.githubusercontent.com:sub" # Returns the "subject" claim in the OIDC token, which typically contains information about the repository and the ref (branch or tag) that triggered the GitHub Actions workflow. Its came in pattern of "repo:{owner}/{repo}:ref:refs/heads/{branch}" for branches and "repo:{owner}/{repo}:ref:refs/tags/{tag}" for tags.
      values = [
        "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_owner}/${var.github_repo}:ref:refs/tags/v*",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json # Create the IAM role with the policy document we created above.
}

data "aws_iam_policy_document" "ecr_push" { 
  statement {                               # Here we define policies for the same role, that allow GitHub Actions to connect to ECR and push images.
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",          # This allow GitHub to connect to ECR.
    ]
    resources = ["*"]                       # Allow to connect to all ECR repositories, but the push permissions will be limited only to the repositories we specify in the next statement. 
  }

  statement {
    effect = "Allow"
    actions = [                             # List of policies that allow to push images to ECR.
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
    ]
    resources = var.ecr_repository_arns     # The list of repo ARNs - only for these repositories GitHub Actions will have permissions to push images.
  }
}

resource "aws_iam_policy" "ecr_push" {      # Here we create the policy that we defined above, but we don't attach it to the role yet. 
  name   = "${var.role_name}-ecr-push"
  policy = data.aws_iam_policy_document.ecr_push.json
}

resource "aws_iam_role_policy_attachment" "attach" {          # Here we attach the policy to the role we created above.
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.ecr_push.arn
}
