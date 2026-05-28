output "ticketing_notifications_topic_arn" {
    value = aws_sns_topic.ticketing_notifications.arn
    description = "ARN of the SNS topic for ticketing notifications"    
}
