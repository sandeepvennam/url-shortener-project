# Data Resource for Caller Identity
data "aws_caller_identity" "current" {}

resource "aws_dynamodb_table" "url_table" {
  name           = "url-shortener"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "short_url"

  attribute {
    name = "short_url"
    type = "S"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "LambdaExecutionRole"

  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_exec_policy" {
  role       = aws_iam_role.lambda_exec.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  role       = aws_iam_role.lambda_exec.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_lambda_function" "url_shortener_lambda" {
  function_name = "url-shortener"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_exec.arn
  filename      = "lambda.zip"

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.url_table.name
    }
  }
}

resource "aws_api_gateway_rest_api" "url_shortener_api" {
  name = "URL Shortener API"
}

resource "aws_api_gateway_resource" "url_shortener_resource" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener_api.id
  parent_id   = aws_api_gateway_rest_api.url_shortener_api.root_resource_id
  path_part   = "shortener"
}

resource "aws_api_gateway_method" "post_method" {
  rest_api_id   = aws_api_gateway_rest_api.url_shortener_api.id
  resource_id   = aws_api_gateway_resource.url_shortener_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "get_method" {
  rest_api_id   = aws_api_gateway_rest_api.url_shortener_api.id
  resource_id   = aws_api_gateway_resource.url_shortener_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.url_shortener_api.id
  resource_id             = aws_api_gateway_resource.url_shortener_resource.id
  http_method             = aws_api_gateway_method.post_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.url_shortener_lambda.invoke_arn
}

resource "aws_api_gateway_integration" "get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.url_shortener_api.id
  resource_id             = aws_api_gateway_resource.url_shortener_resource.id
  http_method             = aws_api_gateway_method.get_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.url_shortener_lambda.invoke_arn
}

resource "aws_lambda_permission" "apigateway_invoke" {
  for_each = {
    get  = "GET"
    post = "POST"
  }
  statement_id  = "AllowExecutionFromAPIGatewayFor${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.url_shortener_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.url_shortener_api.id}/*/${each.value}/*"
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener_api.id
  depends_on = [
    aws_api_gateway_integration.post_integration,
    aws_api_gateway_integration.get_integration
  ]
}

resource "aws_iam_role" "api_gateway_logging_role" {
  name = "APIGatewayCloudWatchLogsRole"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "apigateway.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_logging_policy" {
  role       = aws_iam_role.api_gateway_logging_role.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "account_settings" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_logging_role.arn
}

resource "aws_api_gateway_stage" "api_stage" {
  deployment_id              = aws_api_gateway_deployment.api_deployment.id
  rest_api_id                = aws_api_gateway_rest_api.url_shortener_api.id
  stage_name                 = "prod"
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigateway_logs.arn
    format          = "$context.requestId $context.identity.sourceIp $context.httpMethod $context.resourcePath $context.status $context.responseLength $context.requestTime"
  }
  depends_on = [aws_api_gateway_account.account_settings]
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.url_shortener_lambda.function_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "apigateway_logs" {
  name              = "/aws/apigateway/url-shortener"
  retention_in_days = 14
}
