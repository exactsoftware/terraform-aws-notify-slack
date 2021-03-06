provider "archive" {}

data "aws_sns_topic" "this" {
  count = "${(1 - var.create_sns_topic) * var.create}"

  name = "${var.sns_topic_name}"
}

resource "aws_sns_topic" "this" {
  count = "${var.create_sns_topic * var.create}"

  name = "${var.sns_topic_name}"
}

locals {
  sns_topic_arn = "${element(concat(aws_sns_topic.this.*.arn, data.aws_sns_topic.this.*.arn, list("")), 0)}"
}

resource "aws_sns_topic_subscription" "sns_notify_slack" {
  count = "${var.create}"

  topic_arn = "${local.sns_topic_arn}"
  protocol  = "lambda"
  endpoint  = "${aws_lambda_function.notify_slack.0.arn}"
}

resource "aws_lambda_permission" "sns_notify_slack" {
  count = "${var.create}"

  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.notify_slack.0.function_name}"
  principal     = "sns.amazonaws.com"
  source_arn    = "${local.sns_topic_arn}"
}

data "null_data_source" "lambda_file" {
  inputs {
    filename = "${substr("${path.module}/functions/notify_slack.py", length(path.cwd) + 1, -1)}"
  }
}

data "null_data_source" "lambda_archive" {
  inputs {
    filename = "${substr("${path.module}/functions/notify_slack.zip", length(path.cwd) + 1, -1)}"
  }
}

resource "aws_s3_bucket_object" "notify_slack" {
  count = "${var.create}"

  bucket = "${var.s3_bucket}"
  key    = "${var.s3_prefix}notify_slack.zip"
  source = "${data.null_data_source.lambda_archive.outputs.filename}"
  etag   = "${md5(file("${data.null_data_source.lambda_archive.outputs.filename}"))}"
}

resource "aws_lambda_function" "notify_slack" {
  count = "${var.create}"

  function_name = "${var.lambda_function_name}"

  s3_bucket = "${var.s3_bucket}"
  s3_key    = "${aws_s3_bucket_object.notify_slack.id}"

  role             = "${aws_iam_role.lambda.arn}"
  handler          = "notify_slack.lambda_handler"
  source_code_hash = "${base64sha256(file("${data.null_data_source.lambda_archive.outputs.filename}"))}"
  runtime          = "python3.6"
  timeout          = 30
  kms_key_arn      = "${var.kms_key_arn}"

  environment {
    variables = {
      SLACK_WEBHOOK_URL = "${var.slack_webhook_url}"
      SLACK_CHANNEL     = "${var.slack_channel}"
      SLACK_USERNAME    = "${var.slack_username}"
      SLACK_EMOJI       = "${var.slack_emoji}"
    }
  }

  lifecycle {
    ignore_changes = [
      "filename",
      "last_modified",
    ]
  }
}
