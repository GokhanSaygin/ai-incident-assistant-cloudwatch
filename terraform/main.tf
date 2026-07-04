locals {
  common_tags = {
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Environment = "dev"
  }
}

data "archive_file" "error_generator_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/error_generator.py"
  output_path = "${path.module}/lambda_package.zip"
}

resource "aws_iam_role" "error_generator_role" {
  name = "${var.project_name}-error-generator-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "error_generator_basic_execution" {
  role       = aws_iam_role.error_generator_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "error_generator_logs" {
  name              = "/aws/lambda/${var.project_name}-error-generator"
  retention_in_days = 7

  tags = local.common_tags
}

resource "aws_lambda_function" "error_generator" {
  function_name = "${var.project_name}-error-generator"
  role          = aws_iam_role.error_generator_role.arn
  handler       = "error_generator.lambda_handler"
  runtime       = "python3.11"

  filename         = data.archive_file.error_generator_zip.output_path
  source_code_hash = data.archive_file.error_generator_zip.output_base64sha256

  timeout = 10

  depends_on = [
    aws_iam_role_policy_attachment.error_generator_basic_execution,
    aws_cloudwatch_log_group.error_generator_logs
  ]

  tags = local.common_tags
}

resource "aws_apigatewayv2_api" "incident_api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  tags = local.common_tags
}

resource "aws_apigatewayv2_integration" "error_generator_integration" {
  api_id = aws_apigatewayv2_api.incident_api.id

  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.error_generator.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "generate_error_route" {
  api_id = aws_apigatewayv2_api.incident_api.id

  route_key = "GET /generate-error"
  target    = "integrations/${aws_apigatewayv2_integration.error_generator_integration.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.incident_api.id
  name        = "$default"
  auto_deploy = true

  tags = local.common_tags
}

resource "aws_lambda_permission" "allow_api_gateway_error_generator" {
  statement_id  = "AllowAPIGatewayInvokeErrorGenerator"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.error_generator.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.incident_api.execution_arn}/*/*"
}

data "archive_file" "incident_analyzer_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/incident_analyzer.py"
  output_path = "${path.module}/incident_analyzer_package.zip"
}

resource "aws_dynamodb_table" "incidents" {
  name         = "${var.project_name}-incidents"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "incident_id"

  attribute {
    name = "incident_id"
    type = "S"
  }

  tags = local.common_tags
}

resource "aws_iam_role" "incident_analyzer_role" {
  name = "${var.project_name}-incident-analyzer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "incident_analyzer_basic_execution" {
  role       = aws_iam_role.incident_analyzer_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "incident_analyzer_policy" {
  name = "${var.project_name}-incident-analyzer-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:FilterLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.error_generator_logs.arn}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem"
        ]
        Resource = aws_dynamodb_table.incidents.arn
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "incident_analyzer_policy_attachment" {
  role       = aws_iam_role.incident_analyzer_role.name
  policy_arn = aws_iam_policy.incident_analyzer_policy.arn
}

resource "aws_cloudwatch_log_group" "incident_analyzer_logs" {
  name              = "/aws/lambda/${var.project_name}-incident-analyzer"
  retention_in_days = 7

  tags = local.common_tags
}

resource "aws_lambda_function" "incident_analyzer" {
  function_name = "${var.project_name}-incident-analyzer"
  role          = aws_iam_role.incident_analyzer_role.arn
  handler       = "incident_analyzer.lambda_handler"
  runtime       = "python3.11"

  filename         = data.archive_file.incident_analyzer_zip.output_path
  source_code_hash = data.archive_file.incident_analyzer_zip.output_base64sha256

  timeout     = 30
  memory_size = 256

  environment {
    variables = {
      ERROR_LOG_GROUP  = aws_cloudwatch_log_group.error_generator_logs.name
      INCIDENT_TABLE   = aws_dynamodb_table.incidents.name
      BEDROCK_MODEL_ID = "amazon.nova-micro-v1:0"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.incident_analyzer_basic_execution,
    aws_iam_role_policy_attachment.incident_analyzer_policy_attachment,
    aws_cloudwatch_log_group.incident_analyzer_logs
  ]

  tags = local.common_tags
}

resource "aws_apigatewayv2_integration" "incident_analyzer_integration" {
  api_id = aws_apigatewayv2_api.incident_api.id

  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.incident_analyzer.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "analyze_incident_route" {
  api_id = aws_apigatewayv2_api.incident_api.id

  route_key = "GET /analyze-incident"
  target    = "integrations/${aws_apigatewayv2_integration.incident_analyzer_integration.id}"
}

resource "aws_lambda_permission" "allow_api_gateway_incident_analyzer" {
  statement_id  = "AllowAPIGatewayInvokeIncidentAnalyzer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.incident_analyzer.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.incident_api.execution_arn}/*/*"
}