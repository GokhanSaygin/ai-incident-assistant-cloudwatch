output "api_endpoint" {
  description = "API Gateway endpoint"
  value       = aws_apigatewayv2_api.incident_api.api_endpoint
}

output "generate_error_url" {
  description = "URL to generate a simulated error"
  value       = "${aws_apigatewayv2_api.incident_api.api_endpoint}/generate-error"
}

output "error_generator_log_group" {
  description = "CloudWatch log group for error generator Lambda"
  value       = aws_cloudwatch_log_group.error_generator_logs.name
}

output "analyze_incident_url" {
  description = "URL to analyze recent CloudWatch error logs with Bedrock"
  value       = "${aws_apigatewayv2_api.incident_api.api_endpoint}/analyze-incident"
}

output "incident_table_name" {
  description = "DynamoDB table for incident summaries"
  value       = aws_dynamodb_table.incidents.name
}