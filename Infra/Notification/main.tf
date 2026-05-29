resource "aws_sns_topic" "ticketing_notifications" {
  name                        = "ticketing-notifications"
  fifo_topic                  = false
}

resource "aws_sns_topic_subscription" "ticketing_notifications_subscription" {
  topic_arn = aws_sns_topic.ticketing_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}