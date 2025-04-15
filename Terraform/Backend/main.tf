resource "aws_cognito_user_pool" "movies_user_pool" {
  name                    = "movies-user-pool"
  username_attributes     = ["email"]  
  auto_verified_attributes = ["email"] 

  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  mfa_configuration = "OFF"

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = false
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_LINK"  
  }
}


resource "aws_cognito_user_pool_client" "movies_user_pool_client" {
  name                                 = "movies-user-pool-client"
  user_pool_id                         = aws_cognito_user_pool.movies_user_pool.id
  generate_secret                      = false
  callback_urls = [
  "http://localhost:3000",
  "https://d2o37u6vz3ge6c.cloudfront.net"
]

  logout_urls                          = ["http://localhost:3000"]
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH", 
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  refresh_token_validity = 30
  access_token_validity  = 1
  id_token_validity      = 1
}

resource "aws_cognito_identity_pool" "movies_identity_pool" {
  identity_pool_name               = "movies-identity-pool"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    client_id     = aws_cognito_user_pool_client.movies_user_pool_client.id
    provider_name = "cognito-idp.${var.primary_region}.amazonaws.com/${aws_cognito_user_pool.movies_user_pool.id}"
  }
}

resource "aws_cognito_user_pool_domain" "movies_cognito_domain" {
  domain       = "movies-auth-log"
  user_pool_id = aws_cognito_user_pool.movies_user_pool.id
}

resource "aws_dynamodb_table" "movies" {
  name         = "MoviesTable"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "movieId"
    type = "S"
  }

  hash_key = "movieId"
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_lambda_function" "movies_lambda" {
  function_name = "MoviesFunction"
  runtime       = "python3.10"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda_function.lambda_handler"
  filename      = "lambda/lambda.zip"

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.movies.name
    }
  }
}

resource "aws_api_gateway_rest_api" "movies_api" {
  name        = "MoviesAPI"
  description = "API for managing movies"
}

resource "aws_api_gateway_resource" "movies_resource" {
  rest_api_id = aws_api_gateway_rest_api.movies_api.id
  parent_id   = aws_api_gateway_rest_api.movies_api.root_resource_id
  path_part   = "movies"
}

resource "aws_api_gateway_resource" "movies_id_resource" {
  rest_api_id = aws_api_gateway_rest_api.movies_api.id
  parent_id   = aws_api_gateway_resource.movies_resource.id
  path_part   = "{movieId}"
}

variable "cors_response_parameters" {
  default = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }
}

resource "aws_api_gateway_authorizer" "movies_cognito_auth" {
  name            = "MoviesCognitoAuthorizer"
  rest_api_id     = aws_api_gateway_rest_api.movies_api.id
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [aws_cognito_user_pool.movies_user_pool.arn]
  identity_source = "method.request.header.Authorization"
}

resource "aws_api_gateway_method" "get_movies_method" {
  rest_api_id   = aws_api_gateway_rest_api.movies_api.id
  resource_id   = aws_api_gateway_resource.movies_resource.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.movies_cognito_auth.id
}

resource "aws_api_gateway_method" "post_movies_method" {
  rest_api_id   = aws_api_gateway_rest_api.movies_api.id
  resource_id   = aws_api_gateway_resource.movies_resource.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.movies_cognito_auth.id
}

resource "aws_api_gateway_method" "put_movies_method" {
  rest_api_id   = aws_api_gateway_rest_api.movies_api.id
  resource_id   = aws_api_gateway_resource.movies_id_resource.id
  http_method   = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.movies_cognito_auth.id
}

resource "aws_api_gateway_method" "delete_movies_method" {
  rest_api_id   = aws_api_gateway_rest_api.movies_api.id
  resource_id   = aws_api_gateway_resource.movies_id_resource.id
  http_method   = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.movies_cognito_auth.id
}

resource "aws_api_gateway_method" "options_movies_method" {
  rest_api_id   = aws_api_gateway_rest_api.movies_api.id
  resource_id   = aws_api_gateway_resource.movies_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "options_movies_id_method" {
  rest_api_id   = aws_api_gateway_rest_api.movies_api.id
  resource_id   = aws_api_gateway_resource.movies_id_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_movies_integration" {
  rest_api_id             = aws_api_gateway_rest_api.movies_api.id
  resource_id             = aws_api_gateway_resource.movies_resource.id
  http_method             = aws_api_gateway_method.options_movies_method.http_method
  integration_http_method = "OPTIONS"
  type                    = "MOCK"

  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

resource "aws_api_gateway_integration" "options_movies_id_integration" {
  rest_api_id             = aws_api_gateway_rest_api.movies_api.id
  resource_id             = aws_api_gateway_resource.movies_id_resource.id
  http_method             = aws_api_gateway_method.options_movies_id_method.http_method
  integration_http_method = "OPTIONS"
  type                    = "MOCK"

   request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

resource "aws_api_gateway_integration" "get_movies_integration" {
  rest_api_id             = aws_api_gateway_rest_api.movies_api.id
  resource_id             = aws_api_gateway_resource.movies_resource.id
  http_method             = aws_api_gateway_method.get_movies_method.http_method
  integration_http_method = "GET"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.movies_lambda.invoke_arn
}

resource "aws_api_gateway_integration" "post_movies_integration" {
  rest_api_id             = aws_api_gateway_rest_api.movies_api.id
  resource_id             = aws_api_gateway_resource.movies_resource.id
  http_method             = aws_api_gateway_method.post_movies_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.movies_lambda.invoke_arn
}

resource "aws_api_gateway_integration" "put_movies_integration" {
  rest_api_id             = aws_api_gateway_rest_api.movies_api.id
  resource_id             = aws_api_gateway_resource.movies_id_resource.id
  http_method             = aws_api_gateway_method.put_movies_method.http_method
  integration_http_method = "PUT"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.movies_lambda.invoke_arn
}

resource "aws_api_gateway_integration" "delete_movies_integration" {
  rest_api_id             = aws_api_gateway_rest_api.movies_api.id
  resource_id             = aws_api_gateway_resource.movies_id_resource.id
  http_method             = aws_api_gateway_method.delete_movies_method.http_method
  integration_http_method = "DELETE"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.movies_lambda.invoke_arn
}

resource "aws_api_gateway_method_response" "options_movies_response" {
  rest_api_id         = aws_api_gateway_rest_api.movies_api.id
  resource_id         = aws_api_gateway_resource.movies_resource.id
  http_method         = "OPTIONS"
  status_code         = "200"
  response_parameters = var.cors_response_parameters
}

resource "aws_api_gateway_method_response" "options_movies_id_response" {
  rest_api_id         = aws_api_gateway_rest_api.movies_api.id
  resource_id         = aws_api_gateway_resource.movies_id_resource.id
  http_method         = aws_api_gateway_method.options_movies_id_method.http_method
  status_code         = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }
}

resource "aws_api_gateway_method_response" "get_movies_response" {
  rest_api_id         = aws_api_gateway_rest_api.movies_api.id
  resource_id         = aws_api_gateway_resource.movies_resource.id
  http_method         = "GET"
  status_code         = "200"
  response_parameters = var.cors_response_parameters
}

resource "aws_api_gateway_method_response" "post_movies_response" {
  rest_api_id         = aws_api_gateway_rest_api.movies_api.id
  resource_id         = aws_api_gateway_resource.movies_resource.id
  http_method         = "POST"
  status_code         = "201"
  response_parameters = var.cors_response_parameters
}

resource "aws_api_gateway_method_response" "put_movies_response" {
  rest_api_id         = aws_api_gateway_rest_api.movies_api.id
  resource_id         = aws_api_gateway_resource.movies_id_resource.id
  http_method         = "PUT"
  status_code         = "200"
  response_parameters = var.cors_response_parameters
}

resource "aws_api_gateway_method_response" "delete_movies_response" {
  rest_api_id         = aws_api_gateway_rest_api.movies_api.id
  resource_id         = aws_api_gateway_resource.movies_id_resource.id
  http_method         = "DELETE"
  status_code         = "200"
  response_parameters = var.cors_response_parameters
}

resource "aws_api_gateway_integration_response" "options_movies_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.movies_api.id
  resource_id = aws_api_gateway_resource.movies_resource.id
  http_method = aws_api_gateway_method.options_movies_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,GET,POST'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
  }

  response_templates = {
    "application/json" = ""
  }

  depends_on = [aws_api_gateway_integration.options_movies_integration]
}

resource "aws_api_gateway_integration_response" "options_movies_id_integration_response" {
  rest_api_id     = aws_api_gateway_rest_api.movies_api.id
  resource_id     = aws_api_gateway_resource.movies_id_resource.id
  http_method     = aws_api_gateway_method.options_movies_id_method.http_method
  status_code     = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,PUT,DELETE,POST'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
  }

  response_templates = {
    "application/json" = ""
  }

  depends_on = [aws_api_gateway_integration.options_movies_id_integration]
}

resource "aws_api_gateway_integration_response" "get_movies_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.movies_api.id
  resource_id = aws_api_gateway_resource.movies_resource.id
  http_method = aws_api_gateway_method.get_movies_method.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,GET,POST,PUT,DELETE'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
  }
  response_templates = {
    "application/json" = ""
  }
}

resource "aws_api_gateway_integration_response" "post_movies_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.movies_api.id
  resource_id = aws_api_gateway_resource.movies_resource.id
  http_method = aws_api_gateway_method.post_movies_method.http_method
  status_code = "201"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,GET,POST,PUT,DELETE'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
  }
  response_templates = {
    "application/json" = ""
  }
}

resource "aws_api_gateway_integration_response" "put_movies_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.movies_api.id
  resource_id = aws_api_gateway_resource.movies_id_resource.id
  http_method = aws_api_gateway_method.put_movies_method.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,GET,POST,PUT,DELETE'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
  }
  response_templates = {
    "application/json" = ""
  }
}

resource "aws_api_gateway_integration_response" "delete_movies_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.movies_api.id
  resource_id = aws_api_gateway_resource.movies_id_resource.id
  http_method = aws_api_gateway_method.delete_movies_method.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,GET,POST,PUT,DELETE'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
  }
}

resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.movies_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.movies_api.execution_arn}/*"
}

resource "aws_lambda_permission" "api_gateway_get_permission" {
  statement_id  = "AllowAPIGatewayGetInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.movies_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.movies_api.execution_arn}/*"
}

resource "aws_lambda_permission" "api_gateway_post_permission" {
  statement_id  = "AllowAPIGatewayPostInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.movies_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.movies_api.execution_arn}/*"
}

resource "aws_lambda_permission" "api_gateway_delete_permission" {
  statement_id  = "AllowAPIGatewayDeleteInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.movies_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.movies_api.execution_arn}/*/DELETE/movies/*"

}

resource "aws_lambda_permission" "api_gateway_put_permission" {
  statement_id  = "AllowAPIGatewayPutInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.movies_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.movies_api.execution_arn}/*/PUT/movies/*"

}

resource "aws_api_gateway_deployment" "movies_deployment" {
  rest_api_id = aws_api_gateway_rest_api.movies_api.id
  stage_name  = "prod"
  depends_on = [
    aws_api_gateway_integration.get_movies_integration,
    aws_api_gateway_integration_response.get_movies_integration_response,
    aws_api_gateway_integration.post_movies_integration,
    aws_api_gateway_integration_response.post_movies_integration_response,
    aws_api_gateway_integration.put_movies_integration,
    aws_api_gateway_integration_response.put_movies_integration_response,
    aws_api_gateway_integration.delete_movies_integration,
    aws_api_gateway_integration_response.delete_movies_integration_response,
    aws_api_gateway_integration.options_movies_integration,
    aws_api_gateway_integration_response.options_movies_integration_response,
    aws_api_gateway_integration.options_movies_id_integration,
    aws_api_gateway_integration_response.options_movies_id_integration_response
  ]
}

resource "aws_cloudwatch_log_group" "apigateway_logs" {
  name              = "/aws/apigateway/movies-app"
  retention_in_days = 7
}

resource "aws_api_gateway_stage" "prod_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.movies_api.id
  deployment_id = aws_api_gateway_deployment.movies_deployment.id
  description   = "Production Stage"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigateway_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId",
      caller         = "$context.identity.caller",
      user           = "$context.identity.user",
      requestTime    = "$context.requestTime",
      httpMethod     = "$context.httpMethod",
      resourcePath   = "$context.resourcePath",
      status         = "$context.status",
      protocol       = "$context.protocol",
      responseLength = "$context.responseLength"
    })
  }
}

