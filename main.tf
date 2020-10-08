provider "aws" {
}

# S3 bucket

resource "aws_s3_bucket" "bucket" {
  force_destroy = "true"
	website {
		index_document = "index.html"
	}
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.bucket.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "${aws_s3_bucket.bucket.arn}/*"
    }
  ]
}
POLICY
}

resource "aws_s3_bucket_object" "object" {
  key    = "index.html"
  content = file("index.html")
  bucket = aws_s3_bucket.bucket.bucket
	content_type = "text/html"
}

resource "aws_s3_bucket_object" "api_object" {
  key    = "api.yml"
  content = templatefile("api.yml", {api_url = aws_apigatewayv2_api.api.api_endpoint, users_lambda_arn = "", user_lambda_arn = ""})
  bucket = aws_s3_bucket.bucket.bucket
}

# DDB

resource "aws_dynamodb_table" "users-table" {
  name         = "users-${random_id.id.hex}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userid"

  attribute {
    name = "userid"
    type = "S"
  }
}

# Lambda function

resource "random_id" "id" {
  byte_length = 8
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "/tmp/${random_id.id.hex}-lambda.zip"
  source {
    content  = file("users.js")
    filename = "users.js"
  }
}

resource "aws_lambda_function" "users_lambda" {
  function_name = "api_example-users-${random_id.id.hex}-function"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  handler = "users.handler"
  runtime = "nodejs12.x"
  role    = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      TABLE  = aws_dynamodb_table.users-table.id
    }
  }
}

data "archive_file" "lambda_zip_user" {
  type        = "zip"
  output_path = "/tmp/${random_id.id.hex}-user-lambda.zip"
  source {
    content  = file("user.js")
    filename = "user.js"
  }
}

resource "aws_lambda_function" "user_lambda" {
  function_name = "api_example-user-${random_id.id.hex}-function"

  filename         = data.archive_file.lambda_zip_user.output_path
  source_code_hash = data.archive_file.lambda_zip_user.output_base64sha256

  handler = "user.handler"
  runtime = "nodejs12.x"
  role    = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      TABLE  = aws_dynamodb_table.users-table.id
    }
  }
}

locals {
	lambdas = [aws_lambda_function.users_lambda, aws_lambda_function.user_lambda]
}

data "aws_iam_policy_document" "lambda_exec_role_policy" {
  statement {
    actions = [
      "dynamodb:Scan",
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
    ]
    resources = [
      aws_dynamodb_table.users-table.arn,
    ]
  }
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:*:*:*"
    ]
  }
}

resource "aws_cloudwatch_log_group" "loggroup" {
	count = length(local.lambdas)
  name              = "/aws/lambda/${local.lambdas[count.index].function_name}"
  retention_in_days = 14
}

resource "aws_iam_role_policy" "lambda_exec_role" {
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_exec_role_policy.json
}

resource "aws_iam_role" "lambda_exec" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
	{
	  "Action": "sts:AssumeRole",
	  "Principal": {
		"Service": "lambda.amazonaws.com"
	  },
	  "Effect": "Allow"
	}
  ]
}
EOF
}

# API Gateway

resource "aws_apigatewayv2_api" "api" {
  name          = "api-${random_id.id.hex}"
  protocol_type = "HTTP"
	body = templatefile("api.yml", {users_lambda_arn = aws_lambda_function.users_lambda.arn, user_lambda_arn = aws_lambda_function.user_lambda.arn, api_url = ""})
	cors_configuration {
		allow_origins = ["*"]
		allow_methods = ["GET", "POST", "PUT", "DELETE"]
		allow_headers = ["Content-Type"]
	}
}

resource "aws_apigatewayv2_stage" "example" {
  api_id = aws_apigatewayv2_api.api.id
  name   = "$default"
	auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
	count = length(local.lambdas)
  action        = "lambda:InvokeFunction"
  function_name = local.lambdas[count.index].arn
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

output "url" {
  value = aws_s3_bucket.bucket.website_endpoint
}
